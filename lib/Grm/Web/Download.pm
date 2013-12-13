package Grm::Web::Download;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub package {
    my $self = shift;
    my $req  = $self->req;
    my @obj_ids = $req->param('obj_id');

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { obj_ids => \@obj_ids } );
        },
        html => sub { 
            $self->render( obj_ids => \@obj_ids );
        },
        txt => sub { 
            $self->render( text => Dumper({ obj_ids => \@obj_ids }));
        },
    );
}

1;
