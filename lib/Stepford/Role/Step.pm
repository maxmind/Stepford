package Stepford::Role::Step;

use strict;
use warnings;
use namespace::autoclean;

use Stepford::Trait::StepDependency;
use Stepford::Trait::StepProduction;
use Stepford::Types qw( ArrayOfDependencies Maybe PositiveNum Str );

use Moose::Role;

requires qw( run last_run_time );

sub productions {
    my $class = shift;

    return
        grep { $_->does('Stepford::Trait::StepProduction') }
        $class->meta()->get_all_attributes();
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
interface that the L<Stepford::Scheduler> class expects

=head1 ATTRIBUTES

This role provides one attribute:

=head2 name

This attribute is required for all roles. It must be a string.

=head2 dependencies

This attribute should be an array of one or more I<strings>, each of which is
the name of another step. This attribute is optional.

=head1 METHODS

This role provides the following methods:

=head2 $step->name()

Returns the step's name.

=head2 $step->dependencies()

Returns a list (not an arrayref) of the dependencies passed to the
constructor.

=head2 $step->_has_dependencies

Returns true if the step has dependencies.

=head2 $step->is_up_to_date_since($timestamp)

Given a timestamp as a Unix epoch, this method should return true or false to
indicate whether the step is up to date versus the timestamp.

Note that this timestamp could be a floating point number, and you are
encouraged to use L<Time::HiRes> as appropriate to provide hi-res timestamps
of your own.

=head1 REQUIRED METHODS

All classes which consume the L<Stepford::Role::Step> role must implement the
following methods:

=head2 $step->run()

This method receives no arguments. It is expected to do whatever it is that
the step does.

It may also do other things such as record the last run time.

In the future, this method may receive additional arguments, such as a logger
object.

=head2 $step->last_run_time()

This method must return a timestamp marking the last time the step was
run. You are encouraged to use L<Time::HiRes> as appropriate to provide hi-res
timestamps.
