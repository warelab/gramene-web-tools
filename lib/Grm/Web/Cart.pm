package Grm::Web::Cart;

use Grm::Search;
use Mojo::Base 'Mojolicious::Controller';
use JSON qw( decode_json encode_json );
use MongoDB;
use List::MoreUtils qw( uniq );
use Data::Dumper;
use Grm::DB;

# ----------------------------------------------------------------------
sub view {
    my $self = shift;
    my $cart = $self->_get_cart;

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { cart => $cart } );
        },

        html => sub { $self->render() },

        txt => sub { 
            $self->render( text => Dumper($cart) );
        },
    );
}

# ----------------------------------------------------------------------
sub count {
    my $self  = shift;
    my $cart  = $self->_get_cart;
    my $count = scalar keys %{ $cart->{'items'} || {} };

    $self->render( json => { count => $count } );
}

# ----------------------------------------------------------------------
sub empty {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';

    my ( $cart, $coll ) = $self->_get_cart;

    $coll->remove({ user_id => $user_id });

    $self->render( json => { count => 0 } );
}

# ----------------------------------------------------------------------
sub edit {
    my $self    = shift;
    my $req     = $self->req;
    my $action  = $self->param('action') || 'add';
    my $id      = $self->param('id')     ||    '';

    my ( $cart, $coll ) = $self->_get_cart;
    my $items           = $cart->{'items'} || {}; 
    my $change          = 0;

    if ( $action eq 'add' ) {
        my $params  = $req->params->to_hash;
        my $search  = Grm::Search->new;
        my $results = $search->search( 
            fl      => 'id,title,species,object',
            hl      => 0,
            facet   => 0,
            id      => $id,
            params  => $params,
        );

        for my $doc ( @{ $results->{'response'}{'docs'} } ) {
            $items->{ $doc->{'id'} } = {
                map { $_, $doc->{ $_ } } qw( species object title )
            };
            $change++;
        }
    }
    else {
        if ( $id && defined $items->{ $id } ) {
            delete $items->{ $id };
            $change--;
        }
    }

    $coll->update(
        { _id => $cart->{'_id'} },
        { '$set' => { items => $items } }
    );

    $self->render( 
        json => { 
            change => $change,
            total  => scalar keys %{ $cart->{'items'} || {} },
        } 
    );
}

# ----------------------------------------------------------------------
sub _get_cart {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $client  = MongoDB::MongoClient->new;
    my $db      = $client->get_database('gramene');
    my $coll    = $db->get_collection('carts');
    my $carts   = $coll->find({ user_id => $user_id });

    if ( $carts->count == 0 ) {
        my $id = $coll->insert({
            user_id => $user_id,
            items   => {},
        });

        $carts = $coll->find({ _id => $id });
    }

    my $cart = $carts->next;

    return wantarray ? ( $cart, $coll ) : $cart;
}

1;
