package Stepford::Trait::StepProduction;

use strict;
use warnings;
use namespace::autoclean;

use Moose::Role;

sub Moose::Meta::Attribute::Custom::Trait::StepProduction::register_implementation
{
    return __PACKAGE__;
}

1;
