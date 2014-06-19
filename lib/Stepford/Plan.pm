package Stepford::Plan;

use strict;
use warnings;
use namespace::autoclean;

use Forest::Tree;
use List::AllUtils qw( all uniq );
use Stepford::FinalStep;
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

has _production_map => (
    is       => 'ro',
    isa      => HashRef [Step],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_production_map',
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

    my $tree = $self->_make_tree();

    my @sets;
    while ( $tree->child_count() ) {
        my @leaves;
        $tree->traverse(
            sub {
                my $tree = shift;
                push @leaves, $tree if $tree->is_leaf();
            }
        );

        push @sets, [ sort( uniq( map { $_->node() } @leaves ) ) ];

        for my $leaf (@leaves) {
            my $parent = $leaf->parent();
            $parent->remove_child_at( $parent->get_child_index($leaf) );
        }
    }

    push @sets, [ $tree->node() ];

    $self->logger()
        ->info( 'Plan for '
            . ( join q{ - }, @{ $self->_final_steps() } ) . ': '
            . $self->_step_sets_as_string( \@sets ) );

    return \@sets;
}

sub _make_tree {
    my $self = shift;

    my $tree = Forest::Tree->new(
        node => 'Stepford::FinalStep',
    );

    my %seen;
    $self->_add_steps_to_tree( $tree, $self->_final_steps(), \%seen );

    return $tree;
}

sub _add_steps_to_tree {
    my $self  = shift;
    my $tree  = shift;
    my $steps = shift;
    my $seen  = shift;

    my $map = $self->_production_map();

    for my $step ( @{$steps} ) {
        $self->_check_tree_for_cycle( $tree, $step );

        my $child = Forest::Tree->new(
            node => $step,
        );
        $tree->add_child($child);

        my %deps;
        for my $dep ( map { $_->name() } $step->dependencies() ) {
            Stepford::Error->throw(
                      "Cannot resolve a dependency for $step."
                    . " There is no step that produces the $dep attribute." )
                unless $map->{$dep};

            Stepford::Error->throw(
                "A dependency ($dep) for $step resolved to the same step.")
                if $map->{$dep} eq $step;

            $self->logger()
                ->debug(
                "Dependency $dep for $step is provided by $map->{$dep}");

            $deps{ $map->{$dep} } = 1;
        }

        $self->_add_steps_to_tree( $child, [ keys %deps ], $seen );
    }
}

sub _check_tree_for_cycle {
    my $self = shift;
    my $tree = shift;
    my $step = shift;

    for ( my $cur = $tree ; $cur ; $cur = $cur->parent() ) {
        Stepford::Error->throw(
            "The set of dependencies for $step is cyclical")
            if $cur->node() eq $step;
    }

    return;
}

sub _build_production_map {
    my $self = shift;

    my %map;
    for my $class ( @{ $self->_step_classes() } ) {
        for my $attr ( map { $_->name() } $class->productions() ) {
            next if exists $map{$attr};

            $map{$attr} = $class;
        }
    }

    return \%map;
}

sub _step_sets_as_string {
    my $self = shift;
    my $sets = shift;

    return join ' => ', map { '[ ' . ( join ', ', @{$_} ) . ' ]' } @{$sets};
}

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: Represents a concrete plan for execution by a Stepford::Planner

__END__

=pod

=for Pod::Coverage next_step_set

=head1 DESCRIPTION

This class has no user-facing parts.

=cut
