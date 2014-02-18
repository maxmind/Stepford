package Stepford::Types::Internal;

use strict;
use warnings;

use MooseX::Types::Common::String qw( NonEmptySimpleStr );
use MooseX::Types::Moose qw( ArrayRef Defined Str );
use MooseX::Types::Path::Class qw( File );
use Scalar::Util qw( blessed );

use MooseX::Types -declare => [
    qw(
        ArrayOfDependencies
        ArrayOfFiles
        Step
        )
];

subtype ArrayOfDependencies, as ArrayRef [NonEmptySimpleStr];

coerce ArrayOfDependencies, from NonEmptySimpleStr, via { [$_] };

subtype ArrayOfFiles, as ArrayRef [File], inline_as {
    $_[0]->parent()->_inline_check( $_[1] ) . " && \@{ $_[1] } > 1";
};

coerce ArrayOfFiles, from File, via { [$_] };

role_type Step, { role => 'Stepford::Role::Step' };

1;
