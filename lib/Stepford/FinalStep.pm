package Stepford::FinalStep;

use strict;
use warnings;
use namespace::autoclean;

use Moose;
use MooseX::StrictConstructor;

with 'Stepford::Role::Step';

# We always want this step to run
sub last_run_time {
    return undef;
}

sub run {
    my $self = shift;

    $self->logger()->info('Completed execution');

    return;
}

__PACKAGE__->meta()->make_immutable();

1;
