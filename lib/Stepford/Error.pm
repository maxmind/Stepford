package Stepford::Error;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.005001';

use Moose;

extends 'Throwable::Error';

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );

1;

# ABSTRACT: A Stepford exception object

__END__

=head1 DESCRIPTION

This is a bare subclass of L<Throwable::Error>. It does not add any methods of
its own, for now.
