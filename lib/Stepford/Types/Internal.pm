package Stepford::Types::Internal;

use strict;
use warnings;

use MooseX::Types::Common::String qw( NonEmptyStr );
use MooseX::Types::Moose qw( ArrayRef Defined Str );
use MooseX::Types::Path::Class qw( File );
use Scalar::Util qw( blessed );

use MooseX::Types -declare => [
    qw(
        ArrayOfClassPrefixes
        ArrayOfDependencies
        ArrayOfFiles
        PossibleClassName
        Step
        )
];

subtype PossibleClassName, as Str, inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . ' && '
        . $_[1]
        . ' =~ /^\\p{L}\\w*(?:::\\w+)*$/';
};

subtype ArrayOfClassPrefixes, as ArrayRef [PossibleClassName], inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . " && \@{ $_[1] } >= 1";
};

coerce ArrayOfClassPrefixes, from PossibleClassName, via { [$_] };

subtype ArrayOfDependencies, as ArrayRef [NonEmptyStr];

coerce ArrayOfDependencies, from NonEmptyStr, via { [$_] };

subtype ArrayOfFiles, as ArrayRef [File], inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . " && \@{ $_[1] } >= 1";
};

coerce ArrayOfFiles, from File, via { [$_] };

role_type Step, { role => 'Stepford::Role::Step' };

1;

# ABSTRACT: Internal type definitions for Stepford
