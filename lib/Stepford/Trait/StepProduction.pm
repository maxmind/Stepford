package Stepford::Trait::StepProduction;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.005000';

use Moose::Role;

## no critic (Subroutines::ProhibitQualifiedSubDeclarations)
sub Moose::Meta::Attribute::Custom::Trait::StepProduction::register_implementation
{
    return __PACKAGE__;
}

1;

#ABSTRACT: A trait for attributes which are a step production
