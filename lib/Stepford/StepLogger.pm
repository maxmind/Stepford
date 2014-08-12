package Stepford::StepLogger;

use strict;
use warnings;

use Stepford::Types qw( ClassName Logger );

use Moose;

my $Levels = [qw( debug info notice warning error )];

has _logger => (
    init_arg => 'logger',
    is       => 'ro',
    isa      => Logger,
    required => 1,
    handles  => $Levels,
);

has _class => (
    init_arg => 'class',
    is       => 'ro',
    isa      => ClassName,
    required => 1,
);

around $Levels => sub {
    my $orig    = shift;
    my $self    = shift;
    my $message = shift;

    $message = '[' . $self->_class . '] ' . $message;

    return $self->$orig( $message, @_ );
};

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: The logger used by Step classes.

__END__

=pod

=for Pod::Coverage next_step_set

=head1 DESCRIPTION

This class has no user-facing parts.

=cut
