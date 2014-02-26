package Stepford;

use strict;
use warnings;

1;

# ABSTRACT: A vaguely Rake/Make/Cake-like thing for Perl - create steps and schedule them

__END__

=head1 SYNOPSIS

    package My::Step::MakeSomething;

    use Moose;

    with 'StepFord::Role::Step::FileGenerator';

    sub run {

        # write some files somehow
    }

    package My::Runner;

    use Stepford::Scheduler;

    my @steps = (
        My::Step::Step1->new(
            name => 'step 1',
            ...
        ),
        My::Step::Step2->new(
            name => 'step 2',
            ...
        ),
        My::Step::MakeSomething->new(
            name         => 'Generate a file',
            dependencies => [ 'step 1', 'step 2' ],
        ),
    );

    my $target_step = $steps[-1];

    # Runs all the steps needed to get to the $final_step.
    Stepford::Scheduler->new(
        steps => \@steps,
    )->run($final_step);

=head1 DESCRIPTION

B<NOTE: This is some alpha ju^H^Hcode. You have been warned!>

Stepford provides a framework for running a set of steps that are dependent on
other steps. At a high level, this is a lot like Make, Rake, etc. However, the
actual implementation is fairly different. Currently, there is no DSL, no
Stepfile, etc.

With Stepford, each step is represented by a class you create. That class
should consume either the L<StepFord::Role::Step::FileGenerator> role (if it
generates files) or the L<StepFord::Role::Step> step (if it doesn't).

You then instantiate step objects for each step, giving each step a name and
explicitly specifying its dependencies. Finally, you pass all these steps to a
L<Stepford::Scheduler> and tell it to run a given step. The scheduler runs all
the dependent steps (and their dependencies and so on).

Each step can specify a C<last_run_time()> method (or get one from the
L<StepFord::Role::Step::FileGenerator> role). The scheduler uses this to skip
steps that are up to date.

See L<Stepford::Scheduler>, L<Stepford::Role::Step>, and
L<StepFord::Role::Step::FileGenerator> for more details.

=head1 FUTURE FEATURES

There are several very obvious things that should be added to this framework:

=over 4

=item * Logging

The scheduler and steps should all accept some sort of optional log object and
tell it what they're doing.

=item * Dry runs

This requires logging, of course.

=item * Parallel running

Since the scheduler know what steps depend on what other steps, it can also
figure out when things can be run in parallel.

=back

=head1 VERSIONING POLICY

This module uses semantic versioning as described by
L<http://semver.org/>. Version numbers can be read as X.YYYZZZ, where X is the
major number, YYY is the minor number, and ZZZ is the patch number.

=head1 SUPPORT

Please report all issues with this code using the GitHub issue tracker at
L<https://github.com/maxmind/Stepford/issues>.
