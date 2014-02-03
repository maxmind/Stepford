package Stepford::Types::Internal;

use strict;
use warnings;

use MooseX::Types::Moose qw( ArrayRef Defined Str );
use MooseX::Types::Path::Class qw( File );
use Scalar::Util qw( blessed );

use MooseX::Types -declare => [
    qw(
        ArrayOfDependencies
        ArrayOfFiles
        Dependency
        )
];

subtype Dependency, as Defined, inline_as {
    "( defined $_[1] && !ref $_[1] && length $_[1] )
        || (
        blessed( $_[1] )
        && (   $_[1]->isa(q{Stepford::Step})
            || $_[1]->isa(q{Path::Class::File}) )"
};

subtype ArrayOfDependencies, as ArrayRef [Dependency];

coerce ArrayOfDependencies, from Dependency, via { [$_] };

subtype ArrayOfFiles, as ArrayRef [File], inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . " && \@{ $_[1] } > 1";
};

coerce ArrayOfFiles, from File, via { [$_] };

1;
