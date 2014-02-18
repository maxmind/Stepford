package Stepford::Role::Step::FileGenerator;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( max );
# Sadly, there's no (sane) way to make Path::Class::File use this
use Time::HiRes qw( stat );

use Moose::Role;

with 'Stepford::Role::Step';

sub last_run_time {
    my $self = shift;

    return max( map { ( stat $_ )[9] } $self->_outputs() );
}

1;
