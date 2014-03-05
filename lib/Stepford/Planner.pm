package Stepford::Planner;

use strict;
use warnings;
use namespace::autoclean;

use Graph::Directed;
use List::AllUtils qw( first max );
use Module::Pluggable::Object;
use MooseX::Params::Validate qw( validated_list );
use Scalar::Util qw( blessed );
use Stepford::Error;
use Stepford::Types
    qw( ArrayOfClassPrefixes ArrayRef ClassName HashRef Step );

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

    my @previous_steps;
    my %productions;
    for my $set ( $self->_plan_for_final_step( \%config ) ) {
        my @current_steps;

        # Note that we could easily parallelize this bit
        for my $class ( @{$set} ) {
            my %args;
            for my $dep ( map { $_->name() } $class->dependencies() ) {

                # XXX - I'm not sure this error is reachable. We already check
                # that a class's declared dependencies can be satisfied while
                # building the graph. That said, it doesn't hurt to leave this
                # check in here, and it might help illuminate bugs in the
                # Planner itself.
                Stepford::Error->throw(
                    "Cannot construct a $class object. We are missing a required production: $dep"
                ) unless exists $productions{$dep};

                $args{$dep} = $productions{$dep};
            }

            for my $init_arg (
                grep { defined }
                map  { $_->init_arg() } $class->meta()->get_all_attributes()
                ) {
                $args{$init_arg} = $config{$init_arg}
                    if exists $config{$init_arg};
            }

            my $step = $class->new( \%args );

            my $previous_steps_last_run_time = max(
                grep { defined }
                map  { $_->last_run_time() } @previous_steps
            );

            my $step_last_run_time = $step->last_run_time();

            $step->run()
                unless defined $previous_steps_last_run_time
                && defined $step_last_run_time
                && $step_last_run_time >= $previous_steps_last_run_time;

            for my $production ( $step->productions() ) {
                my $reader = $production->get_read_method();
                $productions{ $production->name() } = $step->$reader()
            }

            push @current_steps, $step;
        }

        @previous_steps = @current_steps;
    }
}

sub _plan_for_final_step {
    my $self = shift;

    my @plan;
    $self->_add_steps_to_plan( $self->final_step(), \@plan );
    push @plan, [ $self->final_step() ];

    $self->_clean_plan( \@plan );

    return @plan;
}

sub _add_steps_to_plan {
    my $self     = shift;
    my $for_step = shift;
    my $plan     = shift;

    my @preds = $self->_graph()->predecessors($for_step)
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

    return $graph;
}

sub _build_step_classes {
    my $self = shift;

    my $sorter = $self->_step_class_sorter();

    # Module::Pluggable does not document whether it returns class names in
    # any specific order.
    return [
        sort { $sorter->() } Module::Pluggable::Object->new(
            search_path => [ $self->step_namespaces() ]
        )->plugins()
    ];
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

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: Takes a set of steps and figures out what order to run them in

__END__

=for Pod::Coverage BUILD add_step

=head1 SYNOPSIS

    use Stepford::Scheduler;

    my @steps = (
        My::Step::Step1->new(
            name => 'step 1',
            ...
        ),
        My::Step::Step2->new(
            name => 'step 2',
            ...
        ),
        My::Step::MakeSomething->new(
            name         => 'Generate a file',
            dependencies => [ 'step 1', 'step 2' ],
        ),
    );

    my $target_step = $steps[-1];

    # Runs all the steps needed to get to the $final_step.
    Stepford::Scheduler->new(
        steps => \@steps,
    )->run($final_step);

=head1 DESCRIPTION

This class takes a set of objects which do the L<Stepford::Role::Step> role
and figured out in what order they should be run in order to get to a final
step.

Steps which are up to date are skipped during the run, so no unnecessary work
is done.

=head1 METHODS

This class provides the following methods:

=head2 Stepford::Scheduler->new(...)

This returns a new scheduler object.

It accepts a single argument, C<steps>. This should be an array reference
containing one or more objects which do the L<Stepford::Role::Step> role.

The constructor checks for circular dependencies among the steps and will
throw a L<Stepford::Error> exception if it finds one.

=head2 $scheduler->run($step)

Given a step object, the scheduler creates an execution plan of all the steps
needed to get to that step.

For each step, the scheduler checks if it is up to date compared to its
dependencies (as determined by the C<< $step->last_run_time() >> method. If
the step is up to date, it is skipped, otherwise the scheduler calls C<<
$step->run() >> on the step.

=head2 $scheduler->steps()

This methods returns a list of the steps in the scheduler.
