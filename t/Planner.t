use strict;
use warnings;

use Test::More;
use Test::Warnings qw( warning );

use Stepford::Planner;

my $runner;
like(
    warning {
        $runner = Stepford::Planner->new( step_namespaces => 'Test1::Step' )
    },
    qr{\QThe Stepford::Planner class has been renamed to Stepford::Runner - use Stepford::Runner at t/Planner.t},
    'got expected warning from Stepford::Planner->new'
);

isa_ok(
    $runner, 'Stepford::Runner',
    'return value of Stepford::Planner->new'
);

done_testing();
