package Stepford::Role::Step;

use strict;
use warnings;
use namespace::autoclean;

use List::AllUtils qw( any );
use Stepford::Trait::StepDependency;
use Stepford::Trait::StepProduction;
use Stepford::Types qw( ArrayOfDependencies Logger Maybe PositiveNum Str );

use Moose::Role;

requires qw( run last_run_time );

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

# Some of these should be moved into a metaclass extension
sub productions {
    my $class = shift;

    return
        grep { $_->does('Stepford::Trait::StepProduction') }
        $class->meta()->get_all_attributes();
}

sub has_production {
    my $class = shift;
    my $name = shift;

    return any { $_->name() eq $name } $class->productions();
}

sub productions_as_hash {
    my $self = shift;

    return
        map { $_->name() => $self->production_value( $_->name() ) }
        $self->productions();
}

sub production_value {
    my $self = shift;
    my $name = shift;

    my $reader
        = $self->meta()->find_attribute_by_name($name)->get_read_method();
    return $self->$reader();
}

sub dependencies {
    my $class = shift;

    return
        grep { $_->does('Stepford::Trait::StepDependency') }
        $class->meta()->get_all_attributes();
}

1;

# ABSTRACT: The basic role all step classes must implement

__END__

=head1 DESCRIPTION

All of your step classes must consume this role. It provides the basic
interface that the L<Stepford::Planner> class expects.

=head1 ATTRIBUTES

This role provides one attribute:

=head2 logger

This attribute is required for all roles. It will be provided to your step
classes by the L<Stepford::Planner> object.

=head1 METHODS

This role provides the following methods:

=head2 $step->productions()

This method returns a list of L<Moose::Meta::Attribute> objects that were
given the C<StepProduction> trait. This can be an empty list.

=head2 $step->has_production($name)

Returns true if the step has a production of the given name.

=head2 $step->productions_as_hash()

Returns all production values as a hash.

=head2 $step->production_value($name)

This method returns the value of the given production for the object it is
called on.

=head2 $step->dependencies()

This method returns a list of L<Moose::Meta::Attribute> objects that were
given the C<StepDependency> trait. This can be an empty list.

=head1 REQUIRED METHODS

All classes which consume the L<Stepford::Role::Step> role must implement the
following methods:

=head2 $step->run()

This method receives no arguments. It is expected to do whatever it is that
the step does.

It may also do other things such as record the last run time.

=head2 $step->last_run_time()

This method must return a timestamp marking the last time the step was
run. You are encouraged to use L<Time::HiRes> as appropriate to provide hi-res
timestamps.
