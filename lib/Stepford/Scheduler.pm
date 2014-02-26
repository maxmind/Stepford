package Stepford::Scheduler;

use strict;
use warnings;
use namespace::autoclean;

use Graph::Directed;
use MooseX::Params::Validate qw( validated_list );
use Scalar::Util qw( blessed );
use Stepford::Error;
use Stepford::Types qw( ArrayRef HashRef Step );

use Moose;
use MooseX::StrictConstructor;

has _steps => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayRef [Step],
    init_arg => 'steps',
    handles  => {
        steps     => 'elements',
        _add_step => 'push',
    },
);

has _graph => (
    is       => 'ro',
    isa      => 'Graph::Directed',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_graph',
);

has _step_map => (
    is       => 'ro',
    isa      => HashRef,
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_step_map',
);

sub BUILD {
    my $self = shift;

    $self->_check_dependency_graph('passed to the constructor');

    return;
}

sub add_step {
    my $self = shift;
    my $step = validated_list(
        \@_,
        step => { isa => Step },
    );

    $step->add_scheduler($self);
    $self->_add_step($step);
    $self->_check_dependency_graph(
        'after adding the ' . $step->name() . ' step' );

    return;
}

sub run {
    my $self       = shift;
    my $final_step = validated_list(
        \@_,
        step => { isa => Step },
    );

    my @plan = $self->_plan_for($final_step);

    for my $set (@plan) {

        # Note that we could easily parallelize this bit
        for my $step ( @{$set} ) {
            next if $self->_step_is_fresh($step);

            $step->run();
        }
    }
}

# This is split out primarily so it can be tested.
sub _plan_for {
    my $self       = shift;
    my $final_step = shift;

    my @plan;
    $self->_add_steps_to_plan( $final_step, \@plan );
    push @plan, [$final_step];

    $self->_clean_plan(\@plan);

    return @plan;
}

sub _add_steps_to_plan {
    my $self     = shift;
    my $for_step = shift;
    my $plan     = shift;

    my @preds
        = map { $self->_step_for_name($_) }
        $self->_graph()->predecessors( $for_step->name() )
        or return;

    unshift @{$plan}, \@preds;

    $self->_add_steps_to_plan( $_, $plan )
        for  @preds;

    return;
}

sub _clean_plan {
    my $self = shift;
    my $plan = shift;

    # First we remove steps we've seen from each set in turn.
    my %seen;
    for my $set ( @{$plan} ) {
        @{$set} = grep { !$seen{ $_->name() } } @{$set};

        $seen{ $_->name() } = 1 for @{$set};
    }

    # This might leave a set that is empty so we remove that entirely.
    @{$plan} = grep { @{$_} } @{$plan};

    return;
}

sub _step_is_fresh {
    my $self = shift;
    my $step = shift;

    for my $dep ( $self->_resolved_dependencies_for($step) ) {
        return 0 unless $step->is_up_to_date_since( $dep->last_run_time() );
    }
}

sub _resolved_dependencies_for {
    my $self = shift;
    my $step = shift;

    return map { $self->_step_for_name($_) } $step->dependencies();
}

sub _step_for_name {
    my $self = shift;
    my $dep  = shift;

    if ( blessed($dep) ) {
        return $dep if $dep->can('does') && $dep->does('Stepford::Role::Step');

        Stepford::Error->throw(
            "Cannot resolve a dependency that is not a string or an object that does the Stepford::Role::Step role (got $dep)"
        );
    }
    else {
        return $self->_step_map()->{$dep}
            if $self->_step_map()->{$dep};
    }

    Stepford::Error->throw("Could not find a dependency matching $dep");
}

sub _build_graph {
    my $self = shift;

    my $graph = Graph::Directed->new();

    for my $step ( $self->steps() ) {
        for my $dep ( $self->_resolved_dependencies_for($step) ) {
            $graph->add_edge( $dep->name() => $step->name() );
        }
    }

    return $graph;
}

sub _check_dependency_graph {
    my $self = shift;
    my $for  = shift;

    Stepford::Error->throw("The set of dependencies $for is cyclical")
        if $self->_graph()->is_cyclic();

    return;
}

sub _build_step_map {
    my $self = shift;

    return { map { $_->name() => $_ } $self->steps() };
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
