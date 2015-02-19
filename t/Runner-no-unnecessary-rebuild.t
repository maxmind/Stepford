use strict;
use warnings;

use Log::Dispatch;
use Path::Class qw( tempdir );
use Stepford::Runner;
use Time::HiRes qw( sleep );

use Test::More;

my $dir   = tempdir( CLEANUP => 1 );
my $file1 = $dir->file('file1');
my $file2 = $dir->file('file2');
my $file3 = $dir->file('file3');

my $iteration = 1;

{
    package Test::Step::Step1;
    use Stepford::Types qw( File );
    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has file1 => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $file1 },
    );

    sub run {
        return if -f $_[0]->file1();
        $_[0]->file1()->spew( __PACKAGE__ . " - $iteration\n" );
    }
}

{
    package Test::Step::Step2;
    use Stepford::Types qw( File );
    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has file1 => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has file2 => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $file2 },
    );

    sub run {
        $_[0]->file2()
            ->spew(
            $_[0]->file1()->slurp() . __PACKAGE__ . " - $iteration\n" );
    }
}

{
    package Test::Step::Step3;
    use Stepford::Types qw( File );
    use Moose;
    with 'Stepford::Role::Step::FileGenerator';

    has file2 => (
        traits   => ['StepDependency'],
        is       => 'ro',
        isa      => File,
        required => 1,
    );

    has file3 => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $file3 },
    );

    sub run {
        $_[0]->file3()
            ->spew(
            $_[0]->file2()->slurp() . __PACKAGE__ . " - $iteration\n" );
        $iteration++;
    }
}

{
    my $runner = Stepford::Runner->new(
        step_namespaces => 'Test::Step',
    );

    $runner->run(
        final_steps => 'Test::Step::Step3',
    );

    for my $file ( $file1, $file2, $file3 ) {
        ok(
            -f $file,
            $file->basename() . ' exists after running all steps'
        );
    }

    my $expect = <<'EOF';
Test::Step::Step1 - 1
Test::Step::Step2 - 1
Test::Step::Step3 - 1
EOF

    is(
        scalar $file3->slurp(),
        $expect,
        $file3->basename() . ' contains expected content'
    );

    $runner->run(
        final_steps => 'Test::Step::Step3',
    );

    is(
        scalar $file3->slurp(),
        $expect,
        $file3->basename()
            . ' content does not change if file1 is not regenerated on second run'
    );

    $file1->remove();

    $runner->run(
        final_steps => 'Test::Step::Step3',
    );

    $expect = <<'EOF';
Test::Step::Step1 - 2
Test::Step::Step2 - 2
Test::Step::Step3 - 2
EOF

    is(
        scalar $file3->slurp(),
        $expect,
        $file3->basename()
            . ' content does change when file1 is regenerated on third run'
    );

    sleep 0.01;
    $file2->touch();

    $runner->run(
        final_steps => 'Test::Step::Step3',
    );

    $expect = <<'EOF';
Test::Step::Step1 - 2
Test::Step::Step2 - 2
Test::Step::Step3 - 3
EOF

    is(
        scalar $file3->slurp(),
        $expect,
        $file3->basename()
            . ' content does change when file3 is regenerated on fourth run'
    );
}

done_testing();
