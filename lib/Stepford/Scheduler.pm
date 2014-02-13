package Stepford::Scheduler;

use strict;
use warnings;

use Graph::Directed;
use Scalar::Util qw( blessed );
use Stepford::Types qw( ArrayRef HashRef Step );

use Moose;

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

    $_->set_scheduler($self) for $self->steps();

    $self->_check_dependency_graph('passed to the constructor');

    return;
}

sub add_step {
    my $self = shift;
    my $step = shift;

    $step->add_scheduler($self);
    $self->_add_step($step);
    $self->_check_dependency_graph(
        'after adding the ' . $step->name() . ' step' );

    return;
}

sub run {
    my $self       = shift;
    my $final_step = shift;

    my @plan = $self->_plan_for($final_step);

    my %done;
    for my $set (@plan) {

        # Note that we could easily parallelize this bit
        for my $step ( @{$set} ) {

            # If a step is a dependency for 2+ other steps it can show up more
            # than once, but we know we only need to run it once.
            next if $done{ $step->name() };
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

    return @plan;
}

sub _add_steps_to_plan {
    my $self     = shift;
    my $for_step = shift;
    my $plan     = shift;

    my @preds
        = map { $self->step_for_name($_) }
        $self->_graph()->predecessors( $for_step->name() )
        or return;

    unshift @{$plan}, \@preds;

    $self->_add_steps_to_plan( $_, $plan )
        for  @preds;

    return;
}

sub step_for_name {
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
        for my $dep ( $step->resolved_dependencies() ) {
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
