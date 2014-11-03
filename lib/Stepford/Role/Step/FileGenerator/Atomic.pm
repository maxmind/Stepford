package Stepford::Role::Step::FileGenerator::Atomic;

use strict;
use warnings;
use namespace::autoclean;

use Carp qw( croak );
use File::Temp;
use Path::Class qw( dir );
use Stepford::Types qw( File );

use Moose::Role;

with 'Stepford::Role::Step::FileGenerator';

has _temp_dir_handle => (
    is      => 'ro',
    isa     => 'File::Temp::Dir',
    default => sub { File::Temp->new()->newdir() },
);

has pre_commit_file => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    default => sub { dir( shift->_temp_dir_handle() )->file('pre-commit') },
);

sub BUILD { }
before BUILD => sub {
    my $self = shift;

    my @production_names = sort map { $_->name() } $self->productions();

    croak 'The '
        . ( ref $self )
        . ' class consumed the Stepford::Role::Step::FileGenerator::Atomic'
        . " role but contains more than one production: @production_names"
        if @production_names > 1;

    return;
};

after run => sub {
    my $self = shift;

    my $pre_commit = $self->pre_commit_file();

    croak 'The '
        . ( ref $self )
        . ' class consumed the Stepford::Role::Step::FileGenerator::Atomic'
        . ' role but run() produced no pre-commit production file at:'
        . " $pre_commit"
        unless -f $pre_commit;

    my $read_method = ( $self->productions() )[0]->get_read_method();
    my $post_commit = $self->$read_method();

    rename( $pre_commit, $post_commit )
        or croak "Failed renaming $pre_commit -> $post_commit: $!";
};

1;

# ABSTRACT: A role for steps that generate a file atomically

__END__

=head1 DESCRIPTION

This role consumes the L<Stepford::Role::Step::FileGenerator> role. It allows
only one file production, but makes sure it is written atomically - the file
will not exist if the step aborts. The file will only be committed to its
final destination when C<run()> completes successfully.

Instead of manipulating the file production directly, you work with the file
given by C<< $step->pre_commit_file() >>. This role will make sure it gets
committed after C<run()>.

=head1 METHODS

This role provides the following methods:

=head2 $step->BUILD()

This method adds a wrapper to the BUILD method which ensures that there is
only one production.

=head2 $step->pre_commit_file()

This returns a temporary file in a temporary directory that you can manipulate
inside C<run()>. It will be removed if the step fails, or renamed to the final
file production if the step succeeds.
