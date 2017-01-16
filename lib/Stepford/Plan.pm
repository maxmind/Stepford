package Stepford::Plan;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( all uniq );
use Stepford::Error;
use Stepford::FinalStep;
use Stepford::Runner::StepTree ();
use Stepford::Types qw( ArrayRef ArrayOfSteps ClassName HashRef Logger Step );

use Moose;
use MooseX::StrictConstructor;

has _step_classes => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'step_classes',
    required => 1,
);

has _final_steps => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'final_steps',
    required => 1,
);

has _step_sets => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayRef [ ArrayRef [Step] ],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_step_sets',
    handles  => {
        step_sets => 'elements',
    },
);

has _step_tree => (
    is      => 'ro',
    isa     => 'Stepford::Runner::StepTree',
    lazy    => 1,
    builder => '_build_step_tree',
);

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

# This algorithm of using a tree and progressively stripping off leaf nodes
# comes from http://blog.codeaholics.org/parallel-ant/#how-it-works. Many
# thanks to Ran Eilam for pointing me at this blog post!
sub _build_step_sets {
    my $self = shift;

    my $tree = $self->_step_tree;

    my @sets;
    while ( $tree->child_count ) {
        my @leaves;
        $tree->traverse(
            sub {
                my $node = shift;
                push @leaves, $node if $node->is_leaf;
            }
        );

        push @sets, [ sort( uniq( map { $_->step } @leaves ) ) ];

        for my $leaf (@leaves) {
            my $parent = $leaf->parent;
            $parent->remove_child_at( $parent->get_child_index($leaf) );
        }
    }

    push @sets, [ $tree->step ];

    $self->logger->info( 'Plan for '
            . ( join q{ - }, @{ $self->_final_steps } ) . ': '
            . $self->_step_sets_as_string( \@sets ) );

    return \@sets;
}

sub _build_step_tree {
    my $self = shift;

    my $final_step = Stepford::Runner::StepTree->new(
        logger         => $self->logger,
        step           => 'Stepford::FinalStep',
        step_classes   => $self->_step_classes,
        children_steps => [],
    );

    # this is necessary due to the parent param nonsense
    for my $step ( @{ $self->_final_steps } ) {
        $final_step->add_child(
            Stepford::Runner::StepTree->new(
                logger       => $self->logger,
                parent       => $final_step,
                step         => $step,
                step_classes => $self->_step_classes,
            )
        );
    }
    return $final_step;
}

sub _step_sets_as_string {
    my $self = shift;
    my $sets = shift;

    return join ' => ', map { '[ ' . ( join ', ', @{$_} ) . ' ]' } @{$sets};
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Represents a concrete plan for execution by a Stepford::Runner

__END__

=pod

=for Pod::Coverage next_step_set

=head1 DESCRIPTION

This class has no user-facing parts.

=cut
