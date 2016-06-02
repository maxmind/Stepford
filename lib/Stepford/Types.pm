package Stepford::Types;

use strict;
use warnings;

our $VERSION = '0.003008';

use MooseX::Types::Common::Numeric;
use MooseX::Types::Moose;
use MooseX::Types::Path::Class;

use parent 'MooseX::Types::Combine';

__PACKAGE__->provide_types_from(
    qw(
        MooseX::Types::Common::Numeric
        MooseX::Types::Moose
        MooseX::Types::Path::Class
        Stepford::Types::Internal
        )
);

1;

# ABSTRACT: Type library used in Stepford classes/roles
