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
        Step
        )
];

subtype Dependency, as Defined, inline_as {
    <<"EOF";
    ( defined $_[1] && !ref $_[1] && length $_[1] )
        || ( blessed( $_[1] )
        && $_[1]->can('does')
        && $_[1]->does(q{Stepford::Step}) );
EOF
};

subtype ArrayOfDependencies, as ArrayRef [Dependency];

coerce ArrayOfDependencies, from Dependency, via { [$_] };

subtype ArrayOfFiles, as ArrayRef [File], inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . " && \@{ $_[1] } > 1";
};

coerce ArrayOfFiles, from File, via { [$_] };

role_type Step, { role => 'Stepford::Role::Step' };

1;
