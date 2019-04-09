package Stepford::Types::Internal;

use strict;
use warnings;

our $VERSION = '0.006001';

use MooseX::Types::Common::String qw( NonEmptyStr );
use MooseX::Types::Moose qw( ArrayRef Str );
use Moose::Util::TypeConstraints qw( enum );

use MooseX::Types -declare => [
    qw(
        ArrayOfClassPrefixes
        ArrayOfDependencies
        ArrayOfSteps
        Logger
        PossibleClassName
        Step
        )
];

use namespace::clean;

subtype PossibleClassName, as Str, inline_as {
    ## no critic (Subroutines::ProtectPrivateSubs)
    $_[0]->parent->_inline_check( $_[1] ) . ' && '
        . $_[1]
        . ' =~ /^\\p{L}\\w*(?:::\\w+)*$/';
};

subtype ArrayOfClassPrefixes, as ArrayRef [PossibleClassName], inline_as {
    ## no critic (Subroutines::ProtectPrivateSubs)
    $_[0]->parent->_inline_check( $_[1] ) . " && \@{ $_[1] } >= 1";
};

coerce ArrayOfClassPrefixes, from PossibleClassName, via { [$_] };

subtype ArrayOfDependencies, as ArrayRef [NonEmptyStr];

coerce ArrayOfDependencies, from NonEmptyStr, via { [$_] };

duck_type Logger, [qw( debug info notice warning error )];

role_type Step, { role => 'Stepford::Role::Step' };

subtype ArrayOfSteps, as ArrayRef [Step];

coerce ArrayOfSteps, from Step, via { [$_] };

no Moose::Util::TypeConstraints;

1;

# ABSTRACT: Internal type definitions for Stepford
