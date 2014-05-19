package Stepford::Plan;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( all );
use Stepford::Types qw( ArrayRef ArrayOfSteps ClassName Logger );

use Moose;
use MooseX::StrictConstructor;

has _graph => (
    is       => 'ro',
    isa      => 'Graph::Directed',
    init_arg => 'graph',
    required => 1,
);

has _final_steps => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'final_steps',
    required => 1,
);

has _step_sets => (
    is       => 'ro',
    isa      => ArrayRef[ArrayRef[ClassName]],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_step_sets',
);

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

my $FakeFinalStep = '__fake final step__';

sub next_step_set {
    my $self = shift;

    return shift @{ $self->_step_sets() };
}

sub _build_step_sets {
    my $self = shift;

    my @plan = $self->_step_sets_for( $FakeFinalStep );

    $self->logger()
        ->info( 'Plan for '
            . ( join q{ - }, @{ $self->_final_steps() } ) . ': '
            . $self->_step_sets_as_string( \@plan ) );

    return \@plan;
}

# We start by figuring out all the steps we need to get to our final
# steps. The easiest way to do this is to start at our (fake) final step and
# look at that final steps predecessors in the graph. We then repeat that
# recursively for each predecessor until we run out of steps.
#
# This produces a set with a lot of duplicates, but it includes every step we
# need and excludes all those that we don't.
#
# We take the first set of steps from this unoptimized set and push it onto
# the final plan.
#
# From that first set, we look at each step's dependencies. If the dependency
# is needed and hasn't already been added to the plan, we add it to the next
# set. Once we've generated the next set, we push it onto the final plan. We
# repeat this until there are no next steps to add.
sub _step_sets_for {
    my $self     = shift;
    my $for_step = shift;

    my @steps_needed;
    $self->_recurse_predecessors( $for_step, \@steps_needed );

    my %needed = map { $_ => 1 } map { @{$_} } @steps_needed;

    my %planned;

    my @sets;

    my @next_set = @{ $steps_needed[0] };
    while (@next_set) {
        push @sets, [ sort @next_set ];

        @next_set = ();

        for my $step ( @{ $sets[-1] } ) {
            $planned{$step} = 1;

            for my $dependency ( $self->_graph()->successors($step) ) {
                next unless $needed{$dependency};
                next if $planned{$dependency};

                if ( all { $planned{$_} }
                    $self->_graph()->predecessors($dependency) ) {
                    $planned{$dependency} = 1;
                    push @next_set, $dependency;
                }
            }
        }
    }

    return @sets;
}

sub _recurse_predecessors {
    my $self         = shift;
    my $for_step     = shift;
    my $steps_needed = shift;

    my @preds = sort $self->_graph()->predecessors($for_step)
        or return;

    unshift @{$steps_needed}, \@preds;

    $self->_recurse_predecessors( $_, $steps_needed ) for @preds;

    return;
}

sub _step_sets_as_string {
    my $self = shift;
    my $sets = shift;

    return join ' => ', map { '[ ' . ( join ', ', @{$_} ) . ' ]' } @{$sets};
}

__PACKAGE__->meta()->make_immutable();

1;
