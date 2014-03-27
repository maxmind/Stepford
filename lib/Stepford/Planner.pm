package Stepford::Planner;

use strict;
use warnings;
use namespace::autoclean;

use Graph::Directed;
use List::AllUtils qw( first max );
use Module::Pluggable::Object;
use Module::Runtime qw( use_module );
use MooseX::Params::Validate qw( validated_list );
use Scalar::Util qw( blessed );
use Stepford::Error;
use Stepford::Types
    qw( ArrayOfClassPrefixes ArrayRef ClassName HashRef Logger Step );

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

has final_step => (
    is       => 'ro',
    isa      => Step,
    required => 1,
);

has logger => (
    is      => 'ro',
    isa     => Logger,
    lazy    => 1,
    builder => '_build_logger',
);

has _step_classes => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayRef [Step],
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

sub BUILD {
    my $self = shift;

    # We force the graph to be built now so we can detect cyclic dependencies
    # when the planner is constructed, rather than when run() is called.
    $self->_graph();

    return;
}

sub run {
    my $self   = shift;
    my %config = @_;

    my @all_steps;
    my @previous_steps;
    for my $set ( $self->_plan_for_final_step( \%config ) ) {
        my @current_steps;

        # Note that we could easily parallelize this bit
        for my $class ( @{$set} ) {
            my $args = $self->_constructor_args_for_class(
                $class,
                \@all_steps,
                \%config,
            );

            $self->logger()->debug("$class->new()");
            my $step = $class->new($args);

            my $previous_steps_last_run_time = max(
                grep { defined }
                map  { $_->last_run_time() } @previous_steps
            );

            my $step_last_run_time = $step->last_run_time();

            if (   defined $previous_steps_last_run_time
                && defined $step_last_run_time
                && $step_last_run_time >= $previous_steps_last_run_time ) {

                $self->logger()->info(
                          "Last run time for $class is $step_last_run_time."
                        . " Previous steps last run time is $previous_steps_last_run_time."
                        . ' Skipping this step.' );
            }
            else {
                $step->run();
            }

            push @current_steps, $step;
        }

        @previous_steps = @current_steps;
        push @all_steps, @current_steps;
    }
}

sub _plan_for_final_step {
    my $self = shift;

    my @plan;
    $self->_add_steps_to_plan( $self->final_step(), \@plan );
    push @plan, [ $self->final_step() ];

    $self->_clean_plan( \@plan );

    $self->logger()
        ->info( 'Plan for '
            . $self->final_step() . ': '
            . $self->_plan_as_string( \@plan ) );

    return @plan;
}

sub _add_steps_to_plan {
    my $self     = shift;
    my $for_step = shift;
    my $plan     = shift;

    my @preds = sort $self->_graph()->predecessors($for_step)
        or return;

    unshift @{$plan}, \@preds;

    $self->_add_steps_to_plan( $_, $plan ) for @preds;

    return;
}

sub _clean_plan {
    my $self = shift;
    my $plan = shift;

    # First we remove steps we've seen from each set in turn.
    my %seen;
    for my $set ( @{$plan} ) {
        @{$set} = grep { !$seen{$_} } @{$set};

        $seen{$_} = 1 for @{$set};
    }

    # This might leave a set that is empty so we remove that entirely.
    @{$plan} = grep { @{$_} } @{$plan};

    return;
}

sub _plan_as_string {
    my $self = shift;
    my $plan = shift;

    return join ' => ', map { '[ ' . ( join ', ', @{$_} ) . ' ]' } @{$plan};
}

sub _constructor_args_for_class {
    my $self      = shift;
    my $class     = shift;
    my $all_steps = shift;
    my $config    = shift;

    my %args;
    for my $init_arg (
        grep { defined }
        map  { $_->init_arg() } $class->meta()->get_all_attributes()
        ) {
        $args{$init_arg} = $config->{$init_arg}
            if exists $config->{$init_arg};
    }

    # This bit could be optimized by caching the values of productions that
    # we've already seen during this run.
    for my $dep ( map { $_->name() } $class->dependencies() ) {
        my $provider = first { $_->has_production($dep) } @{$all_steps};

        # XXX - I'm not sure this error is reachable. We already check
        # that a class's declared dependencies can be satisfied while
        # building the graph. That said, it doesn't hurt to leave this
        # check in here, and it might help illuminate bugs in the
        # Planner itself.
        Stepford::Error->throw(
            "Cannot construct a $class object. We are missing a required production: $dep"
        ) unless $provider;

        $args{$dep} = $provider->production_value($dep);
    }

    $args{logger} = $self->logger();

    return \%args;
}

sub _build_graph {
    my $self = shift;

    my $graph = Graph::Directed->new();

    my $map = $self->_production_map();

    my @steps = $self->final_step();
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
        final_step      => 'My::Step::MakeSomething',
    )->run();

=head1 DESCRIPTION

This class takes a set of objects which do the L<Stepford::Role::Step> role
and determines what order they should be run so as to get to a final step.

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

=item * final_step

This argument is required.

This is the final step that the planner should run when the C<<
$planner->run() >> method is called. This should be a valid (loaded) class
that does the L<Stepford::Role::Step> role.

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
