package Test1::Step::CreateA1;

use strict;
use warnings;

use Stepford::Types qw( Dir File );
use Time::HiRes qw( stat );

use Moose;

with 'Stepford::Role::Step::FileGenerator';

has tempdir => (
    is       => 'ro',
    isa      => Dir,
    required => 1,
);

has a1_file => (
    traits  => [qw( StepProduction )],
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    default => sub { $_[0]->tempdir->file('a1') },
);

our $RunCount = 0;

sub run {
    my $self = shift;

    return if -f $self->a1_file;

    $self->a1_file->touch;
}

after run => sub { $RunCount++ };

__PACKAGE__->meta->make_immutable;

1;
