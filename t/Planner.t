use strict;
use warnings;

use lib 't/lib';

use File::Temp qw( tempdir );
use Log::Dispatch;
use Log::Dispatch::Array;
use Path::Class qw( dir );
use Stepford::Planner;
use Time::HiRes 1.9726 qw( stat time );

use Test::Differences;
use Test::Fatal;
use Test::More;

my $tempdir = dir( tempdir( CLEANUP => 1 ) );

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

    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test1::Step',
        final_steps     => 'Test1::Step::CombineFiles',
        logger          => $logger,
    );

    _test_plan(
        $planner,
        'Test1::Step',
        [
            [qw( CreateA1 CreateA2 )],
            ['UpdateFiles'],
            ['CombineFiles']
        ],
        'planner comes up with the right plan for simple steps'
    );

    @messages = ();

    $planner->run( tempdir => $tempdir );

    like(
        $messages[0]{message},
        qr/Plan for Test1::Step::CombineFiles/,
        'logged plan when ->run() was called'
    );

    like(
        $messages[0]{message},
        qr/
              \Q[ Test1::Step::CreateA1, Test1::Step::CreateA2 ] => \E
              \Q[ Test1::Step::UpdateFiles ] => [ Test1::Step::CombineFiles ]\E
          /x,
        'logged a readable description of the plan'
    );

    is(
        $messages[0]{level},
        'info',
        'log level for plan description is info'
    );

    is(
        $messages[1]{message},
        'Test1::Step::CreateA1->new()',
        'logged a message indicating that a step was being created'
    );

    is(
        $messages[1]{level},
        'debug',
        'log level for object creation is debug'
    );

    for my $file ( map { $tempdir->file($_) } qw( a1 a2 combined ) ) {
        ok( -f $file, $file->basename() . ' file exists' );
    }

    @messages = ();

    $planner->run( tempdir => $tempdir );

    like(
        $messages[-1]{message},
        qr/^\QLast run time for Test1::Step::CombineFiles is \E.+\QSkipping this step./,
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
    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test2::Step',
        final_steps     => 'Test2::Step::D',
    );

    _test_plan(
        $planner,
        'Test2::Step',
        [
            ['A'],
            ['B'],
            ['C'],
            ['D'],
        ],
        'planner does not include a given step more than once in a plan'
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
        Stepford::Planner->new(
            step_namespaces => 'Test3::Step',
            final_steps     => 'Test3::Step::B',
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
        Stepford::Planner->new(
            step_namespaces => 'Test4::Step',
            final_steps     => 'Test4::Step::A',
        );
    };

    like(
        $e,
        qr/
              \QCannot resolve a dependency for Test4::Step::A. \E
              \QThere is no step that produces the thing_b attribute.\E
          /x,
        'unresolved dependencies cause the planner constructor to die'
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
        Stepford::Planner->new(
            step_namespaces => 'Test5::Step',
            final_steps     => 'Test5::Step::A',
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
    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test6::Step',
        final_steps     => 'Test6::Step::A2',
    );

    is(
        $planner->_production_map()->{thing_a},
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
    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test7::Step',
        final_steps     => 'Test7::Step::A',
    );

    $planner->run(
        content => 'new content',
        ignored => 42,
    );

    is(
        scalar $tempdir->file('test7-step-a')->slurp(),
        'new content',
        'values passed to $planner->run() are passed to step constructor'
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
    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test8::Step',
        final_steps     => [ 'Test8::Step::Final1', 'Test8::Step::Final2' ],
    );

    _test_plan(
        $planner,
        'Test8::Step',
        [
            [ 'ForShared::A', 'ForShared::B' ],
            ['Shared'],
            [ 'ForFinal1::A', 'ForFinal2::A' ],
            [ 'Final1',       'ForFinal2::B' ],
            ['Final2'],
        ],
        'planner comes up with an optimized plan for multiple final steps'
    );
}

done_testing();

sub _test_plan {
    my $planner = shift;
    my $prefix  = shift;
    my $expect  = shift;
    my $desc    = shift;

    $expect = [
        map {
            [ map { $prefix . '::' . $_ } @{$_} ]
        } @{$expect}
    ];

    my $got = $planner->_make_plan()->_step_sets();

    my $got_str    = _plan_as_str($got);
    my $expect_str = _plan_as_str($expect);

    eq_or_diff(
        $got_str,
        $expect_str,
        $desc
    );
}

sub _plan_as_str {
    my $plan = shift;

    my $str = q{};
    for my $set ( @{$plan} ) {
        $str .= join ' - ', @{$set};
        $str .= "\n";
    }

    return $str;
}
