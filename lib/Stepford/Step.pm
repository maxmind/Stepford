package Stepford::Step;

use strict;
use warnings;

use List::AllUtils qw( all max );
use Stepford::Error;
use Stepford::Types qw( ArrayOfDependencies ArrayOfFiles CodeRef Str );
# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose;

has name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has work => (
    is       => 'ro',
    isa      => CodeRef,
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

sub run {
    my $self = shift;

    return if $self->is_fresh();

    my $work = $self->work();
    $self->$work();
    $self->_record_run();

    return;
}

sub is_fresh {
    my $self = shift;

    if ( $self->_has_outputs() ) {
        for my $output ( $self->_outputs() ) {
            return 0 unless -f $output;

            return all { $_->is_older_than($output) }
            $self->_resolved_dependencies();
        }
    }
    else {
        return 0;
    }
}

sub is_older_than {
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

    Stepford::Error->throw(
        'Something asked for resolved dependencies before this step was added to the scheduler'
    ) unless $self->_has_scheduler();

    return [ map { $self->scheduler()->step_for_name($_) }
            $self->_dependencies() ];
}

__PACKAGE__->meta()->make_immutable();

1;
