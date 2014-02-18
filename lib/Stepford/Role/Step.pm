package Stepford::Role::Step;

use strict;
use warnings;
use namespace::autoclean;

use Stepford::Types qw( ArrayOfDependencies ArrayOfFiles Str );

use Moose::Role;

requires qw( run last_run_time );

has name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has _dependencies => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayOfDependencies,
    coerce   => 1,
    init_arg => 'dependencies',
    default  => sub { [] },
    handles  => {
        _has_dependencies => 'count',
        dependencies     => 'elements',
    },
);

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

sub is_up_to_date_since {
    my $self      = shift;
    my $timestamp = shift;

    my $last_run = $self->last_run_time();
    return 0 unless defined $last_run;

    return $last_run > $timestamp;
}

1;
