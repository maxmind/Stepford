package Stepford::Plan;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.003010';

use List::AllUtils qw( all uniq );
use Stepford::Error;
use Stepford::FinalStep;
use Stepford::Runner::StepGraph ();
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

has step_graph => (
    is      => 'ro',
    isa     => 'Stepford::Runner::StepGraph',
    lazy    => 1,
    builder => '_build_step_graph',
);

has logger => (
    is       => 'ro',
    isa      => Logger,
    required => 1,
);

sub _build_step_graph {
    my $self = shift;

    my $final_step = Stepford::Runner::StepGraph->new(
        config         => $self->config,
        logger         => $self->logger,
        step           => 'Stepford::FinalStep',
        step_classes   => $self->_step_classes,
        children_steps => [],
    );

    # this is necessary due to the parent param nonsense
    for my $step ( @{ $self->_final_steps } ) {
        $final_step->add_child(
            Stepford::Runner::StepGraph->new(
                config       => $self->config,
                logger       => $self->logger,
                step         => $step,
                step_classes => $self->_step_classes,
            )
        );
    }
    return $final_step;
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
