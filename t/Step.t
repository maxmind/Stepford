use strict;
use warnings;

use lib 't/lib';

use File::Temp qw( tempdir );
use Path::Class qw( dir );
use Test::Step::TouchFile;
use Time::HiRes qw( stat );

use Test::More;

my $dir = dir( tempdir( CLEANUP => 1 ) );

{
    my $file1 = $dir->file('step1');
    my $step1 = Test::Step::TouchFile->new(
        name    => 'step 1',
        outputs => $file1,
    );

    my $exists1 = $dir->file('exists1');
    $exists1->touch();

    ok(
        !$step1->is_up_to_date_since( ( stat $exists1 )[9] ),
        q{step 1 is older than a file that exists when the step hasn't been run yet}
    );

    $step1->run();
    ok(
        -f $file1,
        'calling run() on step 1 touches file1'
    );
}

done_testing();
