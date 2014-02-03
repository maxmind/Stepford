package Stepford::Error;

use strict;
use warnings;

use Moose;

extends 'Throwable::Error';

__PACKAGE__->meta()->make_immutable();

1;
