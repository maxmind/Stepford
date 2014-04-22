package Stepford::Role::Step::FileGenerator;

use strict;
use warnings;
use namespace::autoclean;

use Carp qw( croak );
use List::AllUtils qw( max );
use Stepford::Types qw( File );
# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes 1.9726 qw( stat );

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
        map  { $self->${ \( $_->get_read_method() ) } } $self->productions();

    return max @times;
}

1;

# ABSTRACT: A role for steps that generate files

__END__

=head1 DESCRIPTION

This role consumes the L<Stepford::Role::Step> role and adds some additional
functionality specific to generating files.

=head1 METHODS

This role provides the following methods:

=head2 $step->BUILD()

This method adds a wrapper to the BUILD method which checks that all of the
class's productions are of the C<File> type provided by
L<MooseX::Types::Path::Class>. The attributes can also be subtypes of this
type.

This check may be changed so that it is done as part of the class definition,
if I can think of a way to do this sanely.

=head2 $step->last_run_time()

This returns the most recent file modification time from all of the step's
productions.
