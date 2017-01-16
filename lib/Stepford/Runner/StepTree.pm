package Stepford::Runner::StepTree;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( first_index max );
use Scalar::Util qw( refaddr );
use Stepford::Error;
use Stepford::Types qw( ArrayRef Maybe Step );

use Moose;
use MooseX::StrictConstructor;

has step => (
    is       => 'ro',
    isa      => Step,
    required => 1,
);

# XXX - this really should not be necessary
has 'parent' => (
    is       => 'ro',
    isa      => Maybe ['Stepford::Runner::StepTree'],
    weak_ref => 1,
);

has children_steps => (
    traits => ['Array'],
    is     => 'ro',
    isa    => ArrayRef ['Stepford::Runner::StepTree'],

    # required => 1,
    lazy    => 1,
    default => sub { [] },
    handles => {

        # XXX - the code should be refactored so modifying the tree is not
        # necessary
        add_child       => 'push',
        child_count     => 'count',
        is_leaf         => 'is_empty',
        remove_child_at => 'delete',
    },
);

sub traverse {
    my $self = shift;
    my $cb   = shift;

    $cb->($self);
    $_->traverse($cb) for @{ $self->children_steps };
    return;
}

sub get_child_index {
    my $self  = shift;
    my $child = shift;

    return first_index { refaddr $child eq refaddr $_}
    @{ $self->children_steps };
}

__PACKAGE__->meta->make_immutable;

1;
