package Stepford::Runner::StepTree;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( first_index max );
use Scalar::Util qw( refaddr );
use Stepford::Error;
use Stepford::Types qw( ArrayOfSteps ArrayRef HashRef Logger Maybe Step );

use Moose;
use MooseX::StrictConstructor;

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

has step => (
    is       => 'ro',
    isa      => Step,
    required => 1,
);

has _step_classes => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'step_classes',
    required => 1,
);

# XXX - this really should not be necessary
has 'parent' => (
    is       => 'ro',
    isa      => Maybe ['Stepford::Runner::StepTree'],
    weak_ref => 1,
);

has _children_steps => (
    traits   => ['Array'],
    init_arg => 'children_steps',
    is       => 'ro',
    isa      => ArrayRef ['Stepford::Runner::StepTree'],

    # required => 1,
    lazy    => 1,
    builder => '_build_children_steps',
    handles => {

        # XXX - the code should be refactored so modifying the tree is not
        # necessary
        add_child       => 'push',
        child_count     => 'count',
        is_leaf         => 'is_empty',
        remove_child_at => 'delete',
    },
);

has _production_map => (
    is       => 'ro',
    isa      => HashRef [Step],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_production_map',
);

sub traverse {
    my $self = shift;
    my $cb   = shift;

    $cb->($self);
    $_->traverse($cb) for @{ $self->_children_steps };
    return;
}

sub get_child_index {
    my $self  = shift;
    my $child = shift;

    return first_index { refaddr $child eq refaddr $_}
    @{ $self->_children_steps };
}

sub _build_production_map {
    my $self = shift;

    my %map;
    for my $class ( @{ $self->_step_classes } ) {
        for my $attr ( map { $_->name } $class->productions ) {
            next if exists $map{$attr};

            $map{$attr} = $class;
        }
    }

    return \%map;
}

sub _build_children_steps {
    my $self = shift;

    my $map  = $self->_production_map;
    my $step = $self->step;

    my @children;
    my %deps;

    # We remove the current class from step classes for children to prevent
    # cycles
    my @step_classes = grep { $step ne $_ } @{ $self->_step_classes };

    for my $dep ( map { $_->name } $step->dependencies ) {
        Stepford::Error->throw( "Cannot resolve a dependency for $step."
                . " There is no step that produces the $dep attribute."
                . " Do you have a cyclic dependency?" )
            unless $map->{$dep};

        Stepford::Error->throw(
            "A dependency ($dep) for $step resolved to the same step.")
            if $map->{$dep} eq $step;

        $self->logger->debug(
            "Dependency $dep for $step is provided by $map->{$dep}");

        my $child_step = $map->{$dep};
        next if exists $deps{$child_step};
        $deps{$child_step} = 1;

        push @children, Stepford::Runner::StepTree->new(
            logger       => $self->logger,
            step         => $child_step,
            step_classes => \@step_classes,
            parent       => $self,
        );
    }

    return \@children;
}

__PACKAGE__->meta->make_immutable;

1;
