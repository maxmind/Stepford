package Stepford::Planner;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003005';

use Carp qw( carp );

use Moose;

extends 'Stepford::Runner';

override new => sub {

    # Needed to escape modifier caller.
    ## no critic (Variables::ProhibitPackageVars)
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    carp
        'The Stepford::Planner class has been renamed to Stepford::Runner - use Stepford::Runner';
    return super();
};

__PACKAGE__->meta()->make_immutable( inline_constructor => 0 );

1;

# ABSTRACT: Renamed to Stepford::Runner

__END__

=pod

=for Pod::Coverage .*

=head1 DESCRIPTION

This class has been renamed to Stepford::Runner. Use that instead.
