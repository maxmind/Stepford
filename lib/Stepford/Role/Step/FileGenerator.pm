package Stepford::Role::Step::FileGenerator;

use strict;
use warnings;
use namespace::autoclean;

use Carp qw( croak );
use List::AllUtils qw( max );
use Stepford::Types qw( File );
# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose::Role;

with 'Stepford::Role::Step';

sub BUILD { }
before BUILD => sub {
    my $self = shift;

    my @not_files = sort map { $_->name() } grep {
        !(     $_->has_type_constraint()
            && $_->type_constraint()->is_a_type_of(File) )
    } $self->productions();

    croak 'The '
        . ( ref $self )
        . ' class consumed the Stepford::Role::Step::FileGenerator role but contains'
        . " the following productions which are not files: @not_files"
            if @not_files;

    return;
};

sub last_run_time {
    my $self = shift;

    my @times = map { ( stat $_ )[9] }
        grep { -f }
        map  { $_->get_read_method_ref()->($self) } $self->productions();

    return max @times;
}

1;

# ABSTRACT: A role for steps that generate files

__END__

=head1 DESCRIPTION

This role consumes the L<Stepford::Role::Step> and adds some additional
functionality specific to generating files.

=head1 ATTRIBUTE

This role provides the following attributes:

=head2 outputs

This is a required attribute. It must contain one or more files that the step
will generate. This can be passed as a single argument or an arrayref
containing multiple files.

Each file can be provided as strings or L<Path::Class::File> objects.

=head1 METHODS

This role provides the following methods:

=head2 $step->last_run_time()

This returns the most recent file modification time from all of the steps
outputs.

=head2 $step->_outputs()

This returns a list of the step's outputs as L<Path::Class::File> objects.
