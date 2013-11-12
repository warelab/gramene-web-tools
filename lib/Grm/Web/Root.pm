package Grm::Web::Root;

use Mojo::Base 'Mojolicious::Controller';

# ----------------------------------------------------------------------
sub home {
    my $self = shift;

    $self->layout('default');
    $self->render();
}

1;
