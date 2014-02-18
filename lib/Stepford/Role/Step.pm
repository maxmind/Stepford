package Stepford::Role::Step;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( max );
use Stepford::Error;
use Stepford::Types
    qw( ArrayOfDependencies ArrayOfFiles Str );

# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose::Role;

requires 'run';

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

sub last_run_time {
    my $self = shift;

    return max( map { ( stat $_ )[9] } $self->_outputs() );
}

1;
