package Stepford::Trait::StepDependency;

use strict;
use warnings;
use namespace::autoclean;

use Moose::Role;

sub Moose::Meta::Attribute::Custom::Trait::StepDependency::register_implementation
{
    return __PACKAGE__;
}

1;
