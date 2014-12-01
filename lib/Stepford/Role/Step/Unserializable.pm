package Stepford::Role::Step::Unserializable;

use strict;
use warnings;
use namespace::autoclean;

use Moose::Role;

1;

# ABSTRACT: A role for steps with unserializable productions

__END__

=head1 DESCRIPTION

If your step class consumes this role, then that step will not be run in a
child process even when running a parallel plan with L<Stepford::Planner>. See
the L<Stepford::Planner> docs for more details.

