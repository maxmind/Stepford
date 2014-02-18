package Stepford::Role::Step::FileGenerator;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( max );
use Stepford::Types qw( ArrayOfFiles );
# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose::Role;

has _outputs => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayOfFiles,
    coerce   => 1,
    init_arg => 'outputs',
    default  => sub { [] },
    handles  => {
        _has_outputs => 'count',
        _outputs     => 'elements',
    },
);

with 'Stepford::Role::Step';

sub last_run_time {
    my $self = shift;

    return max( map { ( stat $_ )[9] } $self->_outputs() );
}

1;
