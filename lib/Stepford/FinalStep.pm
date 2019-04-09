package Stepford::FinalStep;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.006001';

use Moose;
use MooseX::StrictConstructor;

with 'Stepford::Role::Step';

# We always want this step to run
sub last_run_time {
    ## no critic (Subroutines::ProhibitExplicitReturnUndef)
    return undef;
}

sub run {
    my $self = shift;

    $self->logger->info('Completed execution');

    return;
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: The final step for all Stepford runs

__END__

=pod

=for Pod::Coverage .*

=head1 DESCRIPTION

This step just logs the message "Completed execution". It is always run as the
last step when calling C<run> on a L<Stepford::Runner> object.
