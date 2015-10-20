use strict;
use warnings;

use lib 't/lib';

use List::AllUtils qw( first );
use Log::Dispatch;
use Log::Dispatch::Array;
use Path::Class qw( dir tempdir );
use Stepford::Runner;
use Time::HiRes 1.9726 qw( stat time );

use Test::Differences;
use Test::Fatal;
use Test::More;

my $tempdir = tempdir( CLEANUP => 1 );

{
    my @messages;
    my $logger = Log::Dispatch->new(
        outputs => [
            [
                'Array',
                name      => 'array',
                array     => \@messages,
                min_level => 'debug',
            ]
        ]
    );

    require Test1::Step::CombineFiles;

    my $runner = Stepford::Runner->new(
        step_namespaces => 'Test1::Step',
        logger          => $logger,
    );

    _test_plan(
        $runner,
        'Test1::Step',
        ['CombineFiles'],
        [
            [qw( CreateA1 CreateA2 )],
            ['UpdateFiles'],
            ['CombineFiles'],
        ],
        'runner comes up with the right plan for simple steps'
    );

    @messages = ();

    $runner->run(
        final_steps => 'Test1::Step::CombineFiles',
        config => { tempdir => $tempdir },
    );

    my @dep_messages = grep {
               $_->{level} eq 'debug'
            && $_->{message} =~ /^Dependency \w+ for/
    } @messages;

    is(
        scalar @dep_messages,
        4,
        'logged four dependency resolution messages'
    );

    my $plan_message = first { $_->{level} eq 'info' } @messages;
    like(
        $plan_message->{message},
        qr/Plan for Test1::Step::CombineFiles/,
        'logged plan when ->run() was called'
    );

    like(
        $plan_message->{message},
        qr/
              \Q[ Test1::Step::CreateA1, Test1::Step::CreateA2 ] => \E
              \Q[ Test1::Step::UpdateFiles ] => [ Test1::Step::CombineFiles ]\E
          /x,
        'logged a readable description of the plan'
    );

    is(
        $plan_message->{level},
        'info',
        'log level for plan description is info'
    );

    my @object_constructor_messages
        = grep { $_->{level} eq 'debug' && $_->{message} =~ /\Q->new()/ }
        @messages;
    is(
        scalar @object_constructor_messages,
        5,
        'logged five object construction messages'
    );

    is(
        $object_constructor_messages[0]{message},
        'Test1::Step::CreateA1->new()',
        'logged a message indicating that a step was being created'
    );

    is(
        $object_constructor_messages[0]{level},
        'debug',
        'log level for object creation is debug'
    );

    for my $file ( map { $tempdir->file($_) } qw( a1 a2 combined ) ) {
        ok( -f $file, $file->basename() . ' file exists' );
    }

    @messages = ();

    $runner->run(
        final_steps => 'Test1::Step::CombineFiles',
        config => { tempdir => $tempdir },
    );

    ok(
        (
            grep {
                $_->{message}
                    =~ /^\QLast run time for Test1::Step::CombineFiles is \E.+\QSkipping this step./
            } @messages
        ),
        'logged a message when skipping a step'
    );

    is(
        $messages[-1]{level},
        'info',
        'log level for skipping a step is info'
    );

    my %expect_run = (
        CreateA1     => 2,
        CreateA2     => 2,
        UpdateFiles  => 1,
        CombineFiles => 1
    );

    for my $suffix ( sort keys %expect_run ) {
        my $class = 'Test1::Step::' . $suffix;
        my $count = eval '$' . $class . '::RunCount';

        is(
            $count,
            $expect_run{$suffix},
            "$class->run() was called the expected number of times - skipped when up to date"
        );
    }
}

{
    package Test2::Step::A;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test2::Step::B;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits   => ['StepDependency'],
        is       => 'ro',
        required => 1,
    );

    has thing_b => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test2::Step::C;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_b => (
        traits   => ['StepDependency'],
        is       => 'ro',
        required => 1,
    );

    has thing_c => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test2::Step::D;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_b => (
        traits   => ['StepDependency'],
        is       => 'ro',
        required => 1,
    );

    has thing_c => (
        traits   => ['StepDependency'],
        is       => 'ro',
        required => 1,
    );

    has thing_d => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $runner = Stepford::Runner->new(
        step_namespaces => 'Test2::Step',
    );

    _test_plan(
        $runner,
        'Test2::Step',
        'D',
        [
            ['A'],
            ['B'],
            ['C'],
            ['D'],
        ],
        'runner does not include a given step more than once in a plan'
    );
}

{
    package Test3::Step::A;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    has thing_b => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test3::Step::B;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits   => ['StepDependency'],
        is       => 'ro',
        required => 1,
    );

    has thing_b => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $e = exception {
        Stepford::Runner->new(
            step_namespaces => 'Test3::Step',
            )->run(
            final_steps => 'Test3::Step::B',
            );
    };

    like(
        $e,
        qr/\QThe set of dependencies for Test3::Step::\E(?:A|B)\Q is cyclical/,
        'cyclical dependencies cause the Planner constructor to die'
    );
}

{
    package Test4::Step::A;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    has thing_b => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $e = exception {
        Stepford::Runner->new(
            step_namespaces => 'Test4::Step',
            )->run(
            final_steps => 'Test4::Step::A',
            );
    };

    like(
        $e,
        qr/
              \QCannot resolve a dependency for Test4::Step::A. \E
              \QThere is no step that produces the thing_b attribute.\E
          /x,
        'unresolved dependencies cause the runner constructor to die'
    );
}

{
    package Test5::Step::A;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => [qw( StepDependency StepProduction )],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $e = exception {
        Stepford::Runner->new(
            step_namespaces => 'Test5::Step',
            )->run(
            final_steps => 'Test5::Step::A',
            );
    };

    like(
        $e,
        qr/\QA dependency (thing_a) for Test5::Step::A resolved to the same step/,
        'cannot have an attribute that is both a dependency and production'
    );
}

{
    package Test6::Step::A1;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test6::Step::A2;

    use Moose;
    with 'Stepford::Role::Step';

    has thing_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $plan = Stepford::Runner->new(
        step_namespaces => 'Test6::Step',
    )->_make_plan( ['Test6::Step::A2'] );

    is(
        $plan->_production_map()->{thing_a},
        'Test6::Step::A1',
        'when two steps have the same production, choose the one that sorts first'
    );
}

{
    package Test7::Step::A;

    use Stepford::Types qw( File );

    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has content => (
        is      => 'ro',
        default => 'default content',
    );

    has file => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('test7-step-a') },
    );

    sub run {
        $_[0]->file()->spew( $_[0]->content() );
    }

    sub last_run_time { }
}

{
    my $runner = Stepford::Runner->new(
        step_namespaces => 'Test7::Step',
    );

    $runner->run(
        final_steps => 'Test7::Step::A',
        config      => {
            content => 'new content',
            ignored => 42,
        },
    );

    is(
        scalar $tempdir->file('test7-step-a')->slurp(),
        'new content',
        'config passed to $runner->run() is passed to step constructor'
    );
}

{
    package Test8::Step::ForShared::A;

    use Moose;
    with 'Stepford::Role::Step';

    has for_shared_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::ForShared::B;

    use Moose;
    with 'Stepford::Role::Step';

    has for_shared_b => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::Shared;

    use Moose;
    with 'Stepford::Role::Step';

    has for_shared_a => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    has for_shared_b => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    has shared => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::ForFinal1::A;

    use Moose;
    with 'Stepford::Role::Step';

    has shared => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    has for_final1_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::ForFinal2::A;

    use Moose;
    with 'Stepford::Role::Step';

    has shared => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    has for_final2_a => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::ForFinal2::B;

    use Moose;
    with 'Stepford::Role::Step';

    has for_final2_a => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    has for_final2_b => (
        traits => ['StepProduction'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::Final1;

    use Moose;
    with 'Stepford::Role::Step';

    has for_final1_a => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    package Test8::Step::Final2;

    use Moose;
    with 'Stepford::Role::Step';

    has for_final2_b => (
        traits => ['StepDependency'],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $runner = Stepford::Runner->new(
        step_namespaces => 'Test8::Step',
    );

    _test_plan(
        $runner,
        'Test8::Step',
        [ 'Final1', 'Final2' ],
        [
            [ 'ForShared::A', 'ForShared::B' ],
            ['Shared'],
            [ 'ForFinal1::A', 'ForFinal2::A' ],
            [ 'Final1',       'ForFinal2::B' ],
            ['Final2'],
        ],
        'runner comes up with an optimized plan for multiple final steps'
    );
}

{
    package Test9::Step::A;

    use Moose;

    has thing_a => (
        traits => [qw( StepDependency StepProduction )],
        is     => 'ro',
    );

    sub run           { }
    sub last_run_time { }
}

{
    my $e = exception {
        Stepford::Runner->new(
            step_namespaces => 'Test9::Step',
            )->run(
            final_steps => 'Test9::Step::A',
            );
    };

    like(
        $e,
        qr/\QFound a class which doesn't do the Stepford::Role::Step role: Test9::Step::A/,
        'cannot have an attribute that is both a dependency and production'
    );
}

done_testing();

sub _test_plan {
    my $runner      = shift;
    my $prefix      = shift;
    my $final_steps = shift;
    my $expect      = shift;
    my $desc        = shift;

    $expect = [
        map {
            [ map { _prefix( $prefix, $_ ) } @{$_} ]
        } @{$expect}
    ];

    # The final steps for the plan are the last steps in the $expect arrayref.
    my @got = $runner->_make_plan(
        [
            map { _prefix( $prefix, $_ ) }
                ref $final_steps ? @{$final_steps} : $final_steps
        ],
    )->step_sets();

    push @{$expect}, ['Stepford::FinalStep'];

    my $got_str    = _plan_as_str( \@got );
    my $expect_str = _plan_as_str($expect);

    eq_or_diff(
        $got_str,
        $expect_str,
        $desc
    );
}

sub _prefix { return join '::', @_[ 0, 1 ] }

sub _plan_as_str {
    my $plan = shift;

    my $str = q{};
    for my $set ( @{$plan} ) {
        $str .= join ' - ', @{$set};
        $str .= "\n";
    }

    return $str;
}
