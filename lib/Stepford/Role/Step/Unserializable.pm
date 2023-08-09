package Stepford::Role::Step::Unserializable;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.006002';

use Moose::Role;

1;

# ABSTRACT: A role for steps with unserializable productions

__END__

=head1 DESCRIPTION

If your step class consumes this role, then that step will not be run in a
child process even when running a parallel plan with L<Stepford::Runner>. See
the L<Stepford::Runner> docs for more details.

