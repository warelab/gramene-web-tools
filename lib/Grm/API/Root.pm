package Grm::API::Root;

use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub welcome {
    my $self = shift;

    $self->layout('default');
    $self->render();
}

1;
