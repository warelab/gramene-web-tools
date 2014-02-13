package Grm::Web::Cart;

use Mojo::Base 'Mojolicious::Controller';

sub view {
    my $self = shift;

    $self->layout('default');
    $self->render();

#    $self->respond_to(
#        json => sub {
#            $self->render( json => { obj_ids => \@obj_ids } );
#        },
#        html => sub { 
#            $self->render( 
#                #title   => 'Cart',
#                obj_ids => \@obj_ids 
#            );
#        },
#        txt => sub { 
#            $self->render( text => Dumper({ obj_ids => \@obj_ids }));
#        },
#    );
}

1;
