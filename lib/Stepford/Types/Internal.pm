package Stepford::Types::Internal;

use strict;
use warnings;

our $VERSION = '0.003010';

use MooseX::Types::Common::String qw( NonEmptyStr );
use MooseX::Types::Moose qw( ArrayRef Defined Str );
use MooseX::Types::Path::Class qw( File );
use Scalar::Util qw( blessed );

use MooseX::Types -declare => [
    qw(
        ArrayOfClassPrefixes
        ArrayOfDependencies
        ArrayOfFiles
        ArrayOfSteps
        Logger
        PossibleClassName
        Step
        )
];

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

subtype ArrayOfFiles, as ArrayRef [File], inline_as {
    ## no critic (Subroutines::ProtectPrivateSubs)
    $_[0]->parent->_inline_check( $_[1] ) . " && \@{ $_[1] } >= 1";
};

coerce ArrayOfFiles, from File, via { [$_] };

duck_type Logger, [qw( debug info notice warning error )];

role_type Step, { role => 'Stepford::Role::Step' };

subtype ArrayOfSteps, as ArrayRef [Step];

coerce ArrayOfSteps, from Step, via { [$_] };

1;

# ABSTRACT: Internal type definitions for Stepford
