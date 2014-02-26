package Stepford::Types;

use strict;
use warnings;

use MooseX::Types::Moose;

use parent 'MooseX::Types::Combine';

__PACKAGE__->provide_types_from(
    qw(
        MooseX::Types::Moose
        Stepford::Types::Internal
        )
);

1;

# ABSTRACT: Type library used in Stepford classes/roles
