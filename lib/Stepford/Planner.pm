package Stepford::Planner;

use strict;
use warnings;
use namespace::autoclean;

use Graph::Directed;
use List::AllUtils qw( first max );
use Module::Pluggable::Object;
use Module::Runtime qw( use_module );
use MooseX::Params::Validate qw( validated_list );
use Parallel::ForkManager;
use Scalar::Util qw( blessed );
use Stepford::Error;
use Stepford::Plan;
use Stepford::Types qw(
    ArrayOfClassPrefixes ArrayOfSteps ClassName
    HashRef Logger PositiveInt Step
);

use Moose;
use MooseX::StrictConstructor;

has _step_namespaces => (
    traits   => ['Array'],
    is       => 'ro',
    isa      => ArrayOfClassPrefixes,
    coerce   => 1,
    required => 1,
    init_arg => 'step_namespaces',
    handles  => {
        step_namespaces => 'elements',
    },
);

has final_steps => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    coerce   => 1,
    required => 1,
);

has logger => (
    is      => 'ro',
    isa     => Logger,
    lazy    => 1,
    builder => '_build_logger',
);

has jobs => (
    is      => 'ro',
    isa     => PositiveInt,
    default => 1,
);

has _step_classes => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayOfSteps,
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_step_classes',
    handles  => {
        _step_classes => 'elements',
    },
);

has _production_map => (
    is       => 'ro',
    isa      => HashRef [Step],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_production_map',
);

has _graph => (
    is       => 'ro',
    isa      => 'Graph::Directed',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_graph',
);

my $FakeFinalStep = '__fake final step__';

override BUILDARGS => sub {
    my $class = shift;

    my $p = super();

    $p->{final_steps} = delete $p->{final_step}
        if exists $p->{final_step};

    return $p;
};

sub BUILD {
    my $self = shift;

    # We force the graph to be built now so we can detect cyclic dependencies
    # when the planner is constructed, rather than when run() is called.
    $self->_graph();

    return;
}

sub run {
    my $self = shift;

    if ( $self->jobs() > 1 ) {
        $self->_run_parallel(@_);
    }
    else {
        $self->_run_sequential(@_);
    }

    return;
}

sub _run_parallel {
    my $self   = shift;
    my %config = @_;

    my $plan = $self->_make_plan();

    my $pm = Parallel::ForkManager->new( $self->jobs() );

    my %productions;
    my @previous_steps_run_times;
    my @current_steps_run_times;

    while ( my $set = $plan->next_step_set() ) {
        @previous_steps_run_times = @current_steps_run_times;
        @current_steps_run_times  = ();

        $pm->run_on_finish(
            sub {
                my ( $pid, $exit_code, $message ) = @_[ 0, 1, 5 ];

                if ($exit_code) {
                    $pm->wait_all_children();
                    die "Child process $pid failed";
                }
                else {
                    push @current_steps_run_times, $message->{run_time};
                    %productions = (
                        %productions,
                        %{ $message->{productions} },
                    );
                }
            }
        );

        for my $class ( @{$set} ) {
            my $step
                = $self->_make_step_object( $class, \%productions, \%config );

            if (
                $self->_step_is_up_to_date(
                    $step, \@previous_steps_run_times
                )
                ) {

                push @current_steps_run_times, $step->last_run_time();
                %productions = (
                    %productions,
                    $step->productions_as_hash(),
                );
                next;
            }

            if ( my $pid = $pm->start() ) {
                $self->logger()
                    ->debug("Forked child to run $class - pid $pid");
                next;
            }

            $step->run();
            $pm->finish(
                0,
                {
                    last_run_time => $step->last_run_time(),
                    productions   => { $step->productions_as_hash() },
                }
            );
        }

        $self->logger()->debug('Waiting for children');
        $pm->wait_all_children();
    }
}

sub _run_sequential {
    my $self   = shift;
    my %config = @_;

    my $plan = $self->_make_plan();

    my %productions;
    my @previous_steps_run_times;
    my @current_steps_run_times;

    while ( my $set = $plan->next_step_set() ) {
        @previous_steps_run_times = @current_steps_run_times;
        @current_steps_run_times  = ();

        for my $class ( @{$set} ) {
            my $step
                = $self->_make_step_object( $class, \%productions, \%config );

            $step->run()
                unless $self->_step_is_up_to_date(
                $step,
                \@previous_steps_run_times
                );

            push @current_steps_run_times, $step->last_run_time();
            %productions = (
                %productions,
                $step->productions_as_hash(),
            );
        }
    }
}

sub _make_plan {
    my $self = shift;

    return Stepford::Plan->new(
        graph       => $self->_graph(),
        final_steps => $self->final_steps(),
        logger      => $self->logger(),
    );
}

sub _make_step_object {
    my $self        = shift;
    my $class       = shift;
    my $productions = shift;
    my $config      = shift;

    my $args = $self->_constructor_args_for_class(
        $class,
        $productions,
        $config,
    );

    $self->logger()->debug("$class->new()");

    return $class->new($args);
}

sub _constructor_args_for_class {
    my $self        = shift;
    my $class       = shift;
    my $productions = shift;
    my $config      = shift;

    my %args;
    for my $init_arg (
        grep { defined }
        map  { $_->init_arg() } $class->meta()->get_all_attributes()
        ) {

        $args{$init_arg} = $config->{$init_arg}
            if exists $config->{$init_arg};
    }

    for my $dep ( map { $_->name() } $class->dependencies() ) {

        # XXX - I'm not sure this error is reachable. We already check
        # that a class's declared dependencies can be satisfied while
        # building the graph. That said, it doesn't hurt to leave this
        # check in here, and it might help illuminate bugs in the
        # Planner itself.
        Stepford::Error->throw(
            "Cannot construct a $class object. We are missing a required production: $dep"
        ) unless exists $productions->{$dep};

        $args{$dep} = $productions->{$dep};
    }

    $args{logger} = $self->logger();

    return \%args;
}

sub _step_is_up_to_date {
    my $self                     = shift;
    my $step                     = shift;
    my $previous_steps_run_times = shift;

    my $previous_steps_last_run_time
        = max( grep { defined } @{$previous_steps_run_times} );

    my $step_last_run_time = $step->last_run_time();

    if (   defined $previous_steps_last_run_time
        && defined $step_last_run_time
        && $step_last_run_time >= $previous_steps_last_run_time ) {

        my $class = blessed $step;
        $self->logger()
            ->info( "Last run time for $class is $step_last_run_time."
                . " Previous steps last run time is $previous_steps_last_run_time."
                . ' Skipping this step.' );

        return 1;
    }

    return 0;
}

sub _build_graph {
    my $self = shift;

    my $graph = Graph::Directed->new();

    my $map = $self->_production_map();

    my @steps = @{ $self->final_steps() };

    $graph->add_edge( $_ => $FakeFinalStep ) for @steps;

    while ( my $step = shift @steps ) {
        for my $dep ( map { $_->name() } $step->dependencies() ) {
            if ( exists $map->{$dep} ) {
                Stepford::Error->throw(
                    "A dependency ($dep) for $step resolved to the same step."
                ) if $map->{$dep} eq $step;

                push @steps, $map->{$dep};
                $graph->add_edge( $map->{$dep} => $step );

                Stepford::Error->throw(
                    "The set of dependencies for $step is cyclical")
                    if $graph->is_cyclic();
            }
            else {
                Stepford::Error->throw(
                          "Cannot resolve a dependency for $step."
                        . " There is no step that produces the $dep attribute."
                );
            }
        }
    }

    $self->logger()->debug("Graph is $graph");

    return $graph;
}

sub _build_step_classes {
    my $self = shift;

    # Module::Pluggable does not document whether it returns class names in
    # any specific order.
    my $sorter = $self->_step_class_sorter();

    my @classes;

    for my $class (
        sort { $sorter->() } Module::Pluggable::Object->new(
            search_path => [ $self->step_namespaces() ]
        )->plugins()
        ) {

        use_module($class) unless $class->can('run');

        # We need to skip roles
        next unless $class->isa('Moose::Object');

        $self->logger()->debug("Found step class $class");
        push @classes, $class;
    }

    return \@classes;
}

sub _step_class_sorter {
    my $self = shift;

    my $x          = 0;
    my @namespaces = $self->step_namespaces();
    my %order      = map { $_ => $x++ } @namespaces;

    return sub {
        my $a_prefix = first { $a =~ /^\Q$_/ } @namespaces;
        my $b_prefix = first { $b =~ /^\Q$_/ } @namespaces;

        return ( $order{$a_prefix} <=> $order{$b_prefix} or $a cmp $b );
    };
}

sub _build_production_map {
    my $self = shift;

    my %map;
    for my $class ( $self->_step_classes() ) {
        for my $attr ( map { $_->name() } $class->productions() ) {
            next if exists $map{$attr};

            $map{$attr} = $class;
        }
    }

    return \%map;
}

sub _build_logger {
    my $self = shift;

    require Log::Dispatch;
    require Log::Dispatch::Null;
    return Log::Dispatch->new(
        outputs => [ [ Null => min_level => 'emerg' ] ] );
}

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: Takes a set of steps and figures out what order to run them in

__END__

=for Pod::Coverage BUILD add_step

=head1 SYNOPSIS

    use Stepford::Planner;

    Stepford::Planner->new(
        step_namespaces => 'My::Step',
        final_steps =>
            [ 'My::Step::MakeSomething', 'My::Step::MakeSomethingElse' ],
    )->run();

=head1 DESCRIPTION

This class takes a set of objects which do the L<Stepford::Role::Step> role
and determines what order they should be run so as to get to one or more final
steps.

Steps which are up to date are skipped during the run, so no unnecessary work
is done.

=head1 METHODS

This class provides the following methods:

=head2 Stepford::Planner->new(...)

This method returns a new planner object. It accepts the following arguments:

=over 4

=item * step_namespaces

This argument is required.

This can either be a string or an array reference of strings. Each string
should contain a namespace which contains step classes.

For example, if your steps are named C<My::Step::CreateFoo>,
C<My::Step::MergeFooAndBar>, and C<My::Step::DeployMergedFooAndBar>, the
namespace you'd provide is C<'My::Step'>.

The order of the step namespaces I<is> relevant. If more than one step has a
production of the same name, then the first step "wins". Stepford sorts step
class names based on the order of the namespaces provided to the constructor,
and then the full name of the class. You can take advantage of this feature to
provide different steps in a different environments (for example, for testing).

The constructor checks for circular dependencies among the steps and will
throw a L<Stepford::Error> exception if it finds one.

=item * final_steps

This argument is required.

This can either be a string or an array reference of strings. Each string
should be a step's class name. These classes must already be loaded and they
must do the L<Stepford::Role::Step> role.

These are the final steps run when the C<< $planner->run() >> method is
called.

=item * jobs

This argument default to 1.

The number of jobs to run at a time. By default, all steps are run
sequentially. However, if you set this to a value greater than 1 then the
planner will run steps in parallel, up to the value you set.

=item * logger

This argument is optional.

This should be an object that provides C<debug()>, C<info()>, C<notice()>,
C<warning()>, and C<error()> methods.

This object will receive log messages from the planner and (possibly your
steps).

If this is not provided, Stepford will create a L<Log::Dispatch> object with a
single L<Log::Dispatch::Null> output (which silently eats all the logging
messages).

Note that if you I<do> provide a logger object of your own, Stepford will not
load L<Log::Dispatch> into memory.

=back

=head2 $planner->run()

When this method is called, the planner comes up with a plan of the steps
needed to get to the final step given to the constructor and runs them in
order.

For each step, the planner checks if it is up to date compared to its
dependencies (as determined by the C<< $step->last_run_time() >> method. If
the step is up to date, it is skipped, otherwise the planner calls C<<
$step->run() >> on the step.

Note that the step objects are always I<constructed>, so you should avoid
doing a lot of work in your constructor. Save that for the C<run()> method.

=head2 $planner->step_namespaces()

This method returns the step namespaces passed to the constructor as a list
(not an arrayref).

=head2 $planner->final_step()

This method returns the C<final_step> argument passed to the constructor.

=head2 $planner->logger()

This method returns the C<logger> used by the planner, either what you passed
to the constructor or a default.

=head1 PARALLEL RUN CAVEATS

When running steps in parallel, the results of a step (its productions) are
sent from a child process to the parent by serializing them. This means that
productions which can't be serialized (like a L<DBI> handle) will probably
blow up in some way. You'll need to find a way to work around this. For
example, instead of passing a DBI handle you could pass a data structure with
a DSN, username, password, and connection options.

