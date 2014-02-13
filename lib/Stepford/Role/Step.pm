package Stepford::Role::Step;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( all max );
use Stepford::Error;
use Stepford::Types
    qw( ArrayOfDependencies ArrayOfFiles ArrayRef CodeRef Step Str );

# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose::Role;

requires 'run';

has name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has scheduler => (
    is        => 'rw',
    writer    => 'set_scheduler',
    isa       => 'Stepford::Scheduler',
    weak_ref  => 1,
    predicate => '_has_scheduler',
);

has already_ran => (
    traits   => ['Bool'],
    is       => 'ro',
    init_arg => undef,
    default  => 0,
    handles  => {
        _record_run => 'set',
    },
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
        _dependencies     => 'elements',
    },
);

has _resolved_dependencies => (
    traits   => ['Array'],
    is       => 'bare',
    isa      => ArrayRef [Step],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_resolved_dependencies',
    handles  => {
        resolved_dependencies => 'elements',
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

around run => sub {
    my $orig = shift;
    my $self = shift;

    return if $self->is_fresh();

    my @return;
    if (wantarray) {
        @return = $self->$orig(@_);
    }
    elsif ( defined wantarray ) {
        $return[0] = $self->$orig(@_);
    }
    else {
        $self->$orig(@_);
    }

    $self->_record_run();

    return unless defined wantarray;
    return wantarray
        ? @return
        : $return[0];
};

sub is_fresh {
    my $self = shift;

    if ( $self->_has_outputs() ) {
        for my $output ( $self->_outputs() ) {
            return 0 unless -f $output;

            return all { $_->_is_older_than($output) }
            $self->resolved_dependencies();
        }
    }
    else {
        return 0;
    }
}

sub _is_older_than {
    my $self = shift;
    my $file = shift;

    for my $output ( $self->_outputs() ) {
        return 0 unless -f $output;
        return 0 if ( stat($output) )[9] < ( stat($file) )[9];
    }

    return 1;
}

sub _build_resolved_dependencies {
    my $self = shift;

    return [] unless $self->_has_dependencies();

    Stepford::Error->throw(
        'Something asked for resolved dependencies before this step was added to the scheduler'
    ) unless $self->_has_scheduler();

    return [ map { $self->scheduler()->step_for_name($_) }
            $self->_dependencies() ];
}

1;
