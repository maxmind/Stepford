use strict;
use warnings;

use lib 't/lib';

use File::Temp qw( tempdir );
use Path::Class qw( dir );
use Stepford::Planner;

use Test::More;

_test_final_step_dependencies($_) for 1 .. 3;

done_testing();

sub _test_final_step_dependencies {
    my $jobs = shift;

    my $tempdir = dir( tempdir( CLEANUP => 1 ) );

    _run_combine_files( $jobs, $tempdir );

    my $combined_file = $tempdir->file('combined');
    my $t1            = $combined_file->stat()->mtime();
    my $t2            = $t1 + 1000;

    utime 0, $t2, $combined_file;

    _run_combine_files( $jobs, $tempdir );

    is(
        $combined_file->stat()->mtime(),
        $t2, "combined file > updated files => no build, jobs=$jobs"
    );

    my $t3 = $t1 - 1000;
    utime 0, $t3, $combined_file;

    _run_combine_files( $jobs, $tempdir );

    isnt(
        $combined_file->stat()->mtime(),
        $t3, "combined file < updated files => build, jobs=$jobs"
    );
}

sub _run_combine_files {
    my $jobs    = shift;
    my $tempdir = shift;

    my $planner = Stepford::Planner->new(
        step_namespaces => 'Test1::Step',
        jobs            => $jobs,
    );
    $planner->run(
        final_steps => 'Test1::Step::CombineFiles',
        config      => {
            tempdir => $tempdir,
        },
    );
}

=pod

  CreateA2 ----+---> UpdateFiles --------> CombineFiles
  ~~~~~~~~     |     ~~~~~~~~~~~           ~~~~~~~~~~~~
  > a1_file    |     < a1_file             < a1_file_updated
               |     < a2_file             < a2_file_updated
  CreateA1 ----+     > a1_file_updated     > combined_file
  ~~~~~~~~           > a2_file_updated
  > a2_file

=cut
