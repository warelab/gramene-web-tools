package Grm::Web::Cart;

use Mojo::Base 'Mojolicious::Controller';
use JSON qw( decode_json encode_json );
use List::MoreUtils qw( uniq );
use Data::Dumper;
use Grm::DB;

# ----------------------------------------------------------------------
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
#                #title   => 'cart',
#                obj_ids => \@obj_ids 
#            );
#        },
#        txt => sub { 
#            $self->render( text => dumper({ obj_ids => \@obj_ids }));
#        },
#    );
}

# ----------------------------------------------------------------------
sub count {
    my $self  = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';

    my $count = 0;

    if ( $user_id ) {
        my $schema = Grm::DB->new('search')->schema;
        my ($cart) = $schema->resultset('Cart')->find_or_create(
            { user_id => $user_id }
        );
        my @items  = split( /,/, $cart->value() );

        $count = scalar @items;
    }

    $self->render( json => { cart_count => $count  } );
}

# ----------------------------------------------------------------------
sub empty {
    my $self  = shift;
    my $count = 0;

    if ( my $user_id = $self->param('user_id') ) {
        my $db   = Grm::DB->new('search')->dbh;
        my $json = $db->do(
            'delete from cart where user_id=?', {}, $user_id 
        );
    }

    $self->render( json => { cart_count => $count } );
}

# ----------------------------------------------------------------------
sub edit {
    my $self    = shift;
    my $req     = $self->req;
    my $session = $self->session;
    my $user_id = $session->{'user_id'};
    my $action  = $self->param('action') || 'add';
    my @items   = ( $self->param('items') );
    my $total   = 0;

    if ( @items ) {
        my $schema  = Grm::DB->new('search')->schema;
        my ($cart)  = $schema->resultset('Cart')->find_or_create(
            { user_id => $user_id }
        );
        my @current = split( /,/, $cart->value() );

        my @new = ();
        if ( $action eq 'add' ) {
            @new = uniq( @current, @items );
        }
        else {
            my %remove = map { $_, 1 } @items;
            @new = grep { !$remove{ $_ } } @current;
        }

        $total      = scalar @new;
        $cart->value( join(',', @new) );
        $cart->update();
    }

    $self->render( json => { added => scalar @items, total => $total } );
}

1;
