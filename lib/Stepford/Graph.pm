package Stepford::Graph;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.004000';

use List::AllUtils qw( all any first_index max none sort_by );
use Scalar::Util qw( refaddr );
use Stepford::Error;
use Stepford::Types qw(
    ArrayRef
    Bool
    HashRef
    Logger
    Maybe
    Num
    Step
);
use Try::Tiny qw( catch try );

use Moose;
use MooseX::StrictConstructor;

has config => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

has step => (
    is       => 'ro',
    isa      => Step,
    required => 1,
);

has _step_object => (
    is      => 'ro',
    isa     => Step,
    lazy    => 1,
    builder => '_build_step_object',
);

has last_run_time => (
    is      => 'ro',
    isa     => Maybe [Num],
    writer  => 'set_last_run_time',
    clearer => '_clear_last_run_time',
    lazy    => 1,
    default => sub { shift->_step_object->last_run_time },
);

has step_productions_as_hashref => (
    is      => 'ro',
    isa     => HashRef,
    writer  => 'set_step_productions_as_hashref',
    clearer => '_clear_step_productions_as_hashref',
    lazy    => 1,
    default => sub { shift->_step_object->productions_as_hashref },
);

has _children_graphs => (
    traits   => ['Array'],
    init_arg => 'children_graphs',
    is       => 'ro',
    isa      => ArrayRef ['Stepford::Graph'],
    required => 1,
);

has is_being_processed => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
    writer  => 'set_is_being_processed',
);

has has_been_processed => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
    writer  => 'set_has_been_processed',
);

sub _build_step_object {
    my $self = shift;
    my $args = $self->_constructor_args_for_class;

    $self->logger->debug( $self->step . '->new' );
    return $self->step->new($args);
}

sub _constructor_args_for_class {
    my $self = shift;

    my $class  = $self->step;
    my $config = $self->config;

    my %args;
    for my $init_arg (
        grep { defined }
        map  { $_->init_arg } $class->meta->get_all_attributes
        ) {

        $args{$init_arg} = $config->{$init_arg}
            if exists $config->{$init_arg};
    }

    my %productions = $self->_children_productions;

    for my $dep ( map { $_->name } $class->dependencies ) {
        next if exists $args{$dep};

        # XXX - I'm not sure this error is reachable. We already check that a
        # class's declared dependencies can be satisfied while building the
        # graph. That said, it doesn't hurt to leave this check in here, and it
        # might help illuminate bugs in the Runner itself.
        Stepford::Error->throw(
            "Cannot construct a $class object. We are missing a required production: $dep"
        ) unless exists $productions{$dep};

        $args{$dep} = $productions{$dep};
    }

    $args{logger} = $self->logger;

    return \%args;
}

# Note: this is intentionally depth-first traversal
sub traverse {
    my $self = shift;
    my $cb   = shift;

    $_->traverse($cb) for @{ $self->_children_graphs };
    $cb->($self);
    return;
}

sub maybe_run_step {
    my $self                 = shift;
    my $force_step_execution = shift;

    die 'Tried running '
        . $self->step
        . ' when not all children have been processed.'
        unless $self->children_have_been_processed;

    die 'Tried running ' . $self->step . ' when it is currently being run'
        if $self->is_being_processed;

    if ( $self->has_been_processed ) {
        $self->logger->info( $self->step . ' already ran. Skipping.' );
        return;
    }

    if (  !$force_step_execution
        && $self->_is_up_to_date ) {
        $self->logger->info( 'Skipping ' . $self->step );
        $self->set_has_been_processed(1);
        return;
    }

    $self->set_is_being_processed(1);

    $self->logger->info( 'Running ' . $self->step );

    $self->_step_object->run;

    $self->set_is_being_processed(0);
    $self->set_has_been_processed(1);
    $self->_clear_last_run_time;
    $self->_clear_step_productions_as_hashref;

    return;
}

sub _is_up_to_date {
    my $self = shift;

    my $class = $self->step;

    unless ( defined $self->last_run_time ) {
        $self->logger->debug("No last run time for $class.");
        return 0;
    }

    unless ( @{ $self->_children_graphs } ) {
        $self->logger->debug("No previous steps for $class.");
        return 1;
    }

    my @children_last_run_times
        = map { $_->last_run_time } @{ $self->_children_graphs };

    unless ( all { defined } @children_last_run_times ) {
        $self->logger->debug(
            "A previous step for $class does not have a last run time.");
        return 0;
    }

    my $max_previous_step_last_run_time = max(@children_last_run_times);
    $self->logger->info( "Last run time for $class is "
            . $self->last_run_time
            . ". Previous steps last run time is $max_previous_step_last_run_time."
    );
    my $step_is_up_to_date
        = $self->last_run_time > $max_previous_step_last_run_time;

    $self->logger->info( "$class is "
            . ( $step_is_up_to_date ? q{} : 'not ' )
            . 'up to date.' );

    return $step_is_up_to_date;
}

sub productions {
    my $self = shift;

    return (
        $self->_children_productions,
        %{ $self->step_productions_as_hashref },
    );
}

sub _children_productions {
    my $self = shift;

    return
        map { %{ $_->step_productions_as_hashref } }
        @{ $self->_children_graphs };
}

sub children_have_been_processed {
    my $self = shift;

    all { $_->has_been_processed } @{ $self->_children_graphs };
}

sub is_serializable {
    my $self = shift;

    # A step can be serialized as long as it and all of its children do not
    # implement Stepford::Role::Step::Unserializable
    none {
        $_->step->does('Stepford::Role::Step::Unserializable')
    }
    ( $self, @{ $self->_children_graphs } );
}

sub as_string {
    my $self = shift;
    my $depth = shift || 0;

    return ( q{ } x ( 4 * $depth ) ) . $self->step . "\n" . join(
        q{},
        map { $_->as_string( $depth + 1 ) } @{ $self->_children_graphs }
    );
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Contains the step dependency graph

__END__

=pod

=for Pod::Coverage .*

=head1 DESCRIPTION

This is an internal class and has no user-facing parts.
