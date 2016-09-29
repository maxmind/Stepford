package Stepford::Runner::State;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( max );
use Stepford::Error;
use Stepford::Types qw( ArrayRef Bool HashRef Logger );

use Moose;
use MooseX::StrictConstructor;

has force_step_execution => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has logger => (
    is      => 'ro',
    isa     => Logger,
    lazy    => 1,
    builder => '_build_logger',
);

has _productions => (
    is       => 'ro',
    isa      => HashRef,
    init_arg => undef,
    lazy     => 1,
    default  => sub { {} },
);

has _previous_steps_run_times => (
    is       => 'rw',
    isa      => ArrayRef,
    init_arg => undef,
    lazy     => 1,
    default  => sub { [] },
);

has _current_steps_run_times => (
    is       => 'rw',
    isa      => ArrayRef,
    init_arg => undef,
    lazy     => 1,
    default  => sub { [] },
    clearer  => '_clear_current_steps_run_times',
);

sub start_step_set {
    my $self = shift;

    $self->_previous_steps_run_times( $self->_current_steps_run_times );
    $self->_clear_current_steps_run_times;

    return;
}

sub make_step_object {
    my $self   = shift;
    my $class  = shift;
    my $config = shift;

    my $args = $self->_constructor_args_for_class(
        $class,
        $config,
    );

    $self->logger->debug("$class->new");

    return $class->new($args);
}

sub _constructor_args_for_class {
    my $self   = shift;
    my $class  = shift;
    my $config = shift;

    my %args;
    for my $init_arg (
        grep { defined }
        map  { $_->init_arg } $class->meta->get_all_attributes
        ) {

        $args{$init_arg} = $config->{$init_arg}
            if exists $config->{$init_arg};
    }

    my $productions = $self->_productions;

    for my $dep ( map { $_->name } $class->dependencies ) {

        # XXX - I'm not sure this error is reachable. We already check that a
        # class's declared dependencies can be satisfied while building the
        # tree. That said, it doesn't hurt to leave this check in here, and it
        # might help illuminate bugs in the Runner itself.
        Stepford::Error->throw(
            "Cannot construct a $class object. We are missing a required production: $dep"
        ) unless exists $productions->{$dep};

        $args{$dep} = $productions->{$dep};
    }

    $args{logger} = $self->logger;

    return \%args;
}

sub step_is_up_to_date {
    my $self = shift;
    my $step = shift;

    if ( $self->force_step_execution ) {
        $self->logger->debug(
            'Forced step execution enabled. Running this step.');
        return 0;
    }

    my $previous_steps_last_run_time
        = max( grep { defined } @{ $self->_previous_steps_run_times } );

    my $step_last_run_time = $step->last_run_time;

    my $class = blessed $step;
    if (   defined $previous_steps_last_run_time
        && defined $step_last_run_time
        && $step_last_run_time >= $previous_steps_last_run_time ) {

        $self->logger->info(
                  "Last run time for $class is $step_last_run_time."
                . " Previous steps last run time is $previous_steps_last_run_time."
                . ' Skipping this step.' );

        return 1;
    }

    if (   defined $previous_steps_last_run_time
        && defined $step_last_run_time ) {
        $self->logger->debug(
                  "Last run time for $class is $step_last_run_time."
                . " Previous steps last run time is $previous_steps_last_run_time."
                . ' Running this step.' );
    }
    elsif ( defined $previous_steps_last_run_time
        && !defined $step_last_run_time ) {
        $self->logger->debug(
            "No last run time for $class. Running this step.");
    }
    elsif ( !defined $previous_steps_last_run_time
        && defined $step_last_run_time ) {
        $self->logger->debug(
            'No last run time for the previous steps. Running this step.');
    }
    else {
        $self->logger->debug(
            "No last run time for $class or the previous steps. Running this step."
        );
    }

    return 0;
}

sub record_run_time {
    my $self = shift;
    my $time = shift;

    push @{ $self->_current_steps_run_times }, $time;

    return;
}

sub record_productions {
    my $self        = shift;
    my $productions = shift;

    my $current_productions = $self->_productions;
    for my $key ( keys %{$productions} ) {
        $current_productions->{$key} = $productions->{$key};
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Contains data for a single run

__END__

=pod

=for Pod::Coverage .*

=head1 DESCRIPTION

This class is only used by the L<Stepford::Runner> object and has no
user-facing parts.
