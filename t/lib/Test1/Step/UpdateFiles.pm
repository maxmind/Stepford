package Test1::Step::UpdateFiles;

use strict;
use warnings;

use Stepford::Types qw( Dir File );

use Moose;

with 'Stepford::Role::Step::FileGenerator';

has tempdir => (
    is       => 'ro',
    isa      => Dir,
    required => 1,
);

has a1_file => (
    traits   => ['StepDependency'],
    is       => 'ro',
    isa      => File,
    required => 1,
);

has a2_file => (
    traits   => ['StepDependency'],
    is       => 'ro',
    isa      => File,
    required => 1,
);

has a1_file_updated => (
    traits  => ['StepProduction'],
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    default => sub { $_[0]->tempdir()->file('a1-updated') },
);

has a2_file_updated => (
    traits  => ['StepProduction'],
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    default => sub { $_[0]->tempdir()->file('a2-updated') },
);

our $RunCount = 0;

sub run {
    my $self = shift;

    $self->_fill_file($_)
        for $self->a1_file_updated(), $self->a2_file_updated();
}

after run => sub { $RunCount++ };

sub _fill_file {
    my $self = shift;
    my $file = shift;

    $file->spew( $file->basename() . "\n" );
    return $file;
}

__PACKAGE__->meta()->make_immutable();

1;
