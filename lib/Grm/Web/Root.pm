package Grm::Web::Root;

use Mojo::Base 'Mojolicious::Controller';

# ----------------------------------------------------------------------
sub home {
    my $self = shift;

    $self->redirect_to('/search');

#    $self->layout('default');
#    $self->render();
}

1;
