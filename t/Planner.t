use strict;
use warnings;

use lib 't/lib';

use File::Temp qw( tempdir );
use Path::Class qw( dir );
use Stepford::Planner;
use Time::HiRes 1.9722 qw( stat time );

use Test::Fatal;
use Test::More;

my $tempdir = dir( tempdir( CLEANUP => 1 ) );

{
    package Test1::Step::CreateA1;

    use Stepford::Types qw( File );
    use Time::HiRes qw( stat );

    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has a1_file => (
        traits  => [qw( StepProduction )],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('a1') },
    );

    our $RunCount = 0;

    sub run {
        my $self = shift;

        return if -f $self->a1_file();

        $self->a1_file()->touch();
    }

    after run => sub { $RunCount++ };
}

{
    package Test1::Step::CreateA2;

    use Stepford::Types qw( File );

    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has a2_file => (
        traits  => [qw( StepProduction )],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('a2') },
    );

    our $RunCount = 0;

    sub run {
        my $self = shift;

        return if -f $self->a2_file();

        $self->a2_file()->touch();
    }

    after run => sub { $RunCount++ };
}

{
    package Test1::Step::UpdateFiles;

    use Stepford::Types qw( File );

    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has a1_file => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has a2_file => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has a1_file_updated => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('a1-updated') },
    );

    has a2_file_updated => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('a2-updated') },
    );

    our $RunCount = 0;

    sub run {
        my $self = shift;

        $self->_fill_file($_)
            for $self->a1_file_updated(), $self->a2_file_updated();
    }

    after run => sub { $RunCount++ };

    sub _fill_file {
        my $self = shift;
        my $file = shift;

        $file->spew( $file->basename() . "\n" );
        return $file;
    }
}

{
    package Test1::Step::CombineFiles;

    use Stepford::Types qw( File );

    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has a1_file_updated => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has a2_file_updated => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has combined_file => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('combined') },
    );

    our $RunCount = 0;

    sub run {
        my $self = shift;

        $self->combined_file()->spew(
            map { $_->slurp() } $self->a1_file_updated(),
            $self->a2_file_updated()
        );
    }

    after run => sub { $RunCount++ };
}

{
    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test1::Step',
        final_step      => 'Test1::Step::CombineFiles',
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

    $planner->run();

    for my $file ( map { $tempdir->file($_) } qw( a1 a2 combined ) ) {
        ok( -f $file, $file->basename() . ' file exists' );
    }

    $planner->run();

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
        final_step      => 'Test2::Step::D',
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
            final_step      => 'Test3::Step::B',
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
            final_step      => 'Test4::Step::A',
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
            final_step      => 'Test5::Step::A',
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
    my $e = exception {
        Stepford::Planner->new(
            step_namespaces => 'Test6::Step',
            final_step      => 'Test6::Step::A2',
        );
    };

    like(
        $e,
        qr/
              \QBoth Test6::Step::A2 and Test6::Step::A1 both have a production named thing_a. \E
              \QYou cannot have two steps which have the same production.\E
          /x,
        'cannot have two steps with identically named productions'
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

    is_deeply(
        [ $planner->_plan_for_final_step() ],
        $expect,
        $desc
    );
}
