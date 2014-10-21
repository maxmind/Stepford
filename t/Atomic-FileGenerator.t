use strict;
use warnings;

use lib 't/lib';

use Log::Dispatch;
use Log::Dispatch::Null;
use Path::Class qw( tempdir );
use Test::Fatal;

use Test::More;

my $tempdir = tempdir( CLEANUP => 1 );
my $logger =
  Log::Dispatch->new( outputs => [ [ Null => min_level => 'emerg' ] ] );

{
    package AtomicFileGeneratorTest::BadStep;

    use Moose;
    use Stepford::Types qw( File );

    with 'Stepford::Role::Step::FileGenerator::Atomic';

    has [qw( a_production another_production )] => (
        traits => ['StepProduction'],
        is     => 'ro',
        isa    => File,
    );

    sub run { }
}

{
    my $e = exception {
        AtomicFileGeneratorTest::BadStep->new( logger => $logger );
    };
    like(
        $e,
        qr/
            \QThe AtomicFileGeneratorTest::BadStep class consumed the \E
            \QStepford::Role::Step::FileGenerator::Atomic role but contains \E
            \Qmore than one production: a_production another_production\E
           /x,
        'AtomicFileGeneratorTest::BadStep->new() dies because it contains'
          . ' more than one production',
    );
}

{
    package AtomicFileGeneratorTest::TwoLineFileGenerator;

    use Moose;
    use Stepford::Types qw( Bool File );

    with 'Stepford::Role::Step::FileGenerator::Atomic';

    has a_file => (
        traits => ['StepProduction'],
        is     => 'ro',
        isa    => File,
    );

    has should_die => (
        is       => 'ro',
        isa      => Bool,
        required => 1,
    );

    sub run {
        my $self = shift;
        my $file = $self->pre_commit_file();
        $file->spew('line 1');
        die 'expected death' if $self->should_die();
        $file->spew("line 1\nline 2");
    }
}

{
    my $file            = $tempdir->file('no_interruption');
    my $step_that_lives = AtomicFileGeneratorTest::TwoLineFileGenerator->new(
        logger     => $logger,
        should_die => 0,
        a_file     => $file,
    );
    $step_that_lives->run();
    is(
        $file->slurp(),
        "line 1\nline 2",
        'file written correctly to final destination when run() not'
          . ' interrupted',
    );
}

{
    my $file           = $tempdir->file('interruption');
    my $step_that_dies = AtomicFileGeneratorTest::TwoLineFileGenerator->new(
        logger     => $logger,
        should_die => 1,
        a_file     => $file,
    );
    exception { $step_that_dies->run() };
    ok( !-e $file, 'file not written at all when run() interrupted' );
}

done_testing();

