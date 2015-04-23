package Stepford::Planner;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003004';

use Carp qw( carp );

use Moose;

extends 'Stepford::Runner';

override new => sub {
    # Needed to escape modifier caller.
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    carp
        'The Stepford::Planner class has been renamed to Stepford::Runner - use Stepford::Runner';
    return super();
};

1;

# ABSTRACT: Renamed to Stepford::Runner

__END__

=pod

=for Pod::Coverage .*

=head1 DESCRIPTION

This class has been renamed to Stepford::Runner. Use that instead.
