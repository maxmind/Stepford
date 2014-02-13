use strict;
use warnings;

use lib 't/lib';

use File::Temp qw( tempdir );
use Path::Class qw( dir );
use Stepford::Scheduler;
use Test::Step::TouchFile;
use Time::HiRes qw( stat time );

use Test::More;

my $dir = dir( tempdir( CLEANUP => 1 ) );

{
    package Test::Step::SpewEach;

    use Moose;
    with 'Stepford::Role::Step';

    sub run {
        my $self = shift;

        $_->spew( $_->basename() . "\n" ) for $self->_outputs();
    }
}

{
    package Test::Step::Combine;

    use Path::Class qw( file );

    use Moose;
    with 'Stepford::Role::Step';

    has sources => (
        is       => 'ro',
        isa      => 'ArrayRef',
        required => 1,
    );

    sub run {
        my $self = shift;

        ( $self->_outputs() )[0]
            ->spew( map { file($_)->slurp() } @{ $self->sources() } );
    }
}

{
    my $a1      = $dir->file('a1');
    my $step_a1 = Test::Step::TouchFile->new(
        name    => 'build a1',
        outputs => $a1,
    );

    my $a2      = $dir->file('a2');
    my $step_a2 = Test::Step::TouchFile->new(
        name    => 'build a2',
        outputs => $a2,
    );

    my $step_update = Test::Step::SpewEach->new(
        name         => 'update a1 and a2',
        outputs      => [ $a1, $a2 ],
        dependencies => [ $step_a1, $step_a2 ],
        work         => sub {
            $a1->spew("a1\n");
            $a2->spew("a2\n");
        },
    );

    my $combined     = $dir->file('combined');
    my $step_combine = Test::Step::Combine->new(
        name         => 'combine a1 and a2',
        outputs      => $combined,
        dependencies => [$step_update],
        sources      => [ $a1, $a2 ],
    );

    my $scheduler = Stepford::Scheduler->new(
        steps => [ $step_a1, $step_a2, $step_update, $step_combine ],
    );

    my @plan = map {
        [ sort map { $_->name() } @{$_} ]
    } $scheduler->_plan_for($step_combine);

    is_deeply(
        \@plan,
        [
            [ 'build a1', 'build a2' ],
            ['update a1 and a2'],
            ['combine a1 and a2']
        ],
        'scheduler comes up with the right plan for our steps'
    );

    $scheduler->run( step => $step_combine );

    for my $file ( $a1, $a2, $combined ) {
        ok( -f $file, $file->basename() . ' file exists' );
    }
}

done_testing();
