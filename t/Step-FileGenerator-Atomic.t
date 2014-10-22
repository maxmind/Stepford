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

    package AtomicFileGeneratorTest::TooManyFilesStep;

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
        AtomicFileGeneratorTest::TooManyFilesStep->new( logger => $logger );
    };
    like(
        $e,
        qr/
            \QThe AtomicFileGeneratorTest::TooManyFilesStep class consumed \E
            \Qthe Stepford::Role::Step::FileGenerator::Atomic role but \E
            \Qcontains more than one production: a_production \E
            \Qanother_production\E
           /x,
        'AtomicFileGeneratorTest::TooManyFilesStep->new() dies because it'
            . ' contains more than one production',
    );
}

{

    package AtomicFileGeneratorTest::NoWrittenFileStep;

    use Moose;
    use Path::Class qw( tempdir );
    use Stepford::Types qw( File );

    with 'Stepford::Role::Step::FileGenerator::Atomic';

    has a_production => (
        traits  => ['StepProduction'],
        is      => 'ro',
        isa     => File,
        default => sub { $tempdir->file('never_written') },
    );

    sub run { }
}

{
    my $iut =
      AtomicFileGeneratorTest::NoWrittenFileStep->new( logger => $logger );
    my $e = exception { $iut->run() };
    like(
        $e,
        qr/
            \QThe AtomicFileGeneratorTest::NoWrittenFileStep class consumed \E
            \Qthe Stepford::Role::Step::FileGenerator::Atomic role but \E
            \Qrun() produced no pre-commit production file at: \E
           /x,
        'AtomicFileGeneratorTest::NoWrittenFileStep->run() dies because the'
          . ' production file was not found after concrete step run()',
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

    my $pre_commit_dir = $step_that_lives->pre_commit_file()->parent();
    ok( -d $pre_commit_dir, 'pre commit dir exists before run() is called' );

    $step_that_lives->run();
    is(
        $file->slurp(),
        "line 1\nline 2",
        'file written correctly to final destination when run() not'
            . ' interrupted',
    );

    ok( -d $pre_commit_dir, 'pre commit dir exists after run() is called' );

    undef $step_that_lives;
    ok( !-d $pre_commit_dir,
        'pre commit dir cleaned when step goes out of scope' );
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

