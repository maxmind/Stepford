package Stepford::GraphBuilder;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( all sort_by uniq );
use Stepford::Error;
use Stepford::FinalStep;
use Stepford::Graph ();
use Stepford::Types qw( ArrayRef ArrayOfSteps ClassName HashRef Logger Step );

use Moose;
use MooseX::StrictConstructor;

has config => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

has _step_classes => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'step_classes',
    required => 1,
);

has _final_steps => (
    is       => 'ro',
    isa      => ArrayOfSteps,
    init_arg => 'final_steps',
    required => 1,
);

has graph => (
    is      => 'ro',
    isa     => 'Stepford::Graph',
    lazy    => 1,
    builder => '_build_graph',
);

has _production_map => (
    is       => 'ro',
    isa      => HashRef [Step],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_production_map',
);

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

has _graph_cache => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => HashRef,
    default => sub { {} },
    handles => {
        _cache_graph      => 'set',
        _get_cached_graph => 'get',
    },
);

sub _build_graph {
    my $self = shift;

    return Stepford::Graph->new(
        config          => $self->config,
        logger          => $self->logger,
        step            => 'Stepford::FinalStep',
        children_graphs => [
            sort_by { $_->step }
            map { $self->_create_graph( $_, {} ) } @{ $self->_final_steps }
        ],
    );
}

sub _build_production_map {
    my $self = shift;

    my %map;
    for my $class ( @{ $self->_step_classes } ) {
        for my $attr ( map { $_->name } $class->productions ) {
            next if exists $map{$attr};

            $map{$attr} = $class;
        }
    }

    return \%map;
}

sub _create_graph {
    my $self    = shift;
    my $step    = shift;
    my $parents = shift;

    Stepford::Error->throw("The set of dependencies for $step is cyclical")
        if exists $parents->{$step};

    my $childrens_parents = {
        %{$parents},
        $step => 1,
    };

    if ( my $graph = $self->_get_cached_graph($step) ) {
        return $graph;
    }

    my $graph = Stepford::Graph->new(
        config => $self->config,
        logger => $self->logger,
        step   => $step,
        children_graphs =>
            $self->_create_children_graphs( $step, $childrens_parents ),
    );

    $self->_cache_graph( $step => $graph );

    return $graph;
}

sub _create_children_graphs {
    my $self              = shift;
    my $step              = shift;
    my $childrens_parents = shift;

    my @children_steps
        = uniq sort map { $self->_step_for_dependency( $step, $_->name ) }
        $step->dependencies;

    return [ map { $self->_create_graph( $_, $childrens_parents ) }
            @children_steps ];
}

sub _step_for_dependency {
    my $self        = shift;
    my $parent_step = shift;
    my $dep         = shift;

    my $map = $self->_production_map;

    Stepford::Error->throw( "Cannot resolve a dependency for $parent_step."
            . " There is no step that produces the $dep attribute."
            . ' Do you have a cyclic dependency?' )
        unless $map->{$dep};

    Stepford::Error->throw(
        "A dependency ($dep) for $parent_step resolved to the same step.")
        if $map->{$dep} eq $parent_step;

    $self->logger->debug(
        "Dependency $dep for $parent_step is provided by $map->{$dep}");

    return $map->{$dep};
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Represents a concrete plan for execution by a Stepford::Runner

__END__

=pod

=for Pod::Coverage next_step_set

=head1 DESCRIPTION

This class has no user-facing parts.

=cut
