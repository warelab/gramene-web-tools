package Grm::Web::View;

use Mojo::Base 'Mojolicious::Controller';

# ----------------------------------------------------------------------
sub object {
    my $self = shift;

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { 
                module => $self->param('module'),
                table  => $self->param('table'),
                id     => $self->param('id'),
            });
        },

        html => sub {
            $self->render(
                module => $self->param('module'),
                table  => $self->param('table'),
                id     => $self->param('id'),
            );
        },
    );
}

1;
