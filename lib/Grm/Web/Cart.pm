package Grm::Web::Cart;

use Grm::Search;
use Mojo::Base 'Mojolicious::Controller';
use MongoDB;
use List::MoreUtils qw( uniq );
use Data::Dumper;
use Grm::DB;
use Grm::Utils 'timer_calc';
use JSON 'encode_json';

# ----------------------------------------------------------------------
sub db {
    my $self    = shift;
    my $db_file = $self->app->home->rel_file('data/cart.db');
    my $db      = DBI->connect("dbi:SQLite:dbname=$db_file", '', '');
    return $db;
}

# ----------------------------------------------------------------------
sub view {
    my $self     = shift;
    my $session  = $self->session;
    my $user_id  = $session->{'user_id'} || '';
    my $store    = $self->_get_store;
    #my $db       = Grm::DB->new('search')->dbh;
    my $db       = $self->db;

    my $itemizer = sub {
        my $cursor = $store->find({ user_id => $user_id });
        my @items;
        while ( my $item = $cursor->next ) {
            push @items, $item;
        }
        return @items;
    };

    $self->layout('default');

    $self->respond_to(
        json => sub { 
            my $count = $db->selectrow_array(
                'select count(*) from cart where user_id=?', {}, $user_id 
            );
            
            my $cart = $db->selectall_arrayref(
                q[
                    select   count(cart_id) as count, object, species
                    from     cart 
                    where    user_id=?
                    group by 2, 3
                ], 
                { Columns => {} }, 
                $user_id 
            );

            $self->render( json => { count => $count, cart => $cart } );
        },

        html => sub { 
#            my $count = $store->count({ user_id => $user_id });
#            my @cart  = 
#                map {
#                    for my $k ( keys %{ $_->{'_id'} } ) {
#                        $_->{ $k } = $_->{'_id'}{ $k };
#                    }
#                    $_
#                }
#                @{ $store->aggregate([
#                    { '$match' => { 'user_id' => $user_id } },
#                    { '$group' => {
#                        '_id'  => { 
#                            object => '$object', species => '$species' 
#                        },
#                        'count' => { '$sum'  => 1 }
#                    }}
#                ]) };

            $self->render();# count => $count, cart => $cart );
        },

        txt => sub { 
            my @out;
            if ( my @items = $itemizer->() ) {
                my @cols = keys %{ $items[0] };
                push @out, join( "\t", @cols );
                for my $item ( @items ) {
                    push @out, join( "\t", map { $item->{$_} } @cols );
                }
            }

            $self->render( text => join( "\n", @out ) );
        },
    );
}

# ----------------------------------------------------------------------
sub count {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    #my $db      = Grm::DB->new('search')->dbh;
    my $db      = $self->db;
    my $count   = $db->selectrow_array(
        'select count(*) from cart where user_id=?', {}, $user_id 
    );
#    my $store   = $self->_get_store;
#    my $count   = $store->count({ user_id => $user_id });

    $self->render( json => { count => $count } );
}

# ----------------------------------------------------------------------
sub empty {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $store   = $self->_get_store;

    $store->remove({ user_id => $user_id });

    $self->render( json => { count => 0 } );
}

# ----------------------------------------------------------------------
sub edit {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $req     = $self->req;
    my $action  = $self->param('action') || 'add';
    my $id      = $self->param('id')     ||    '';
    my $store   = $self->_get_store;
    #my $db      = Grm::DB->new('search')->dbh;
    my $db      = $self->db;
    my $change  = 0;

    if ( $action eq 'add' ) {
        my $params  = $req->params->to_hash;
        my $search  = Grm::Search->new;
        my $db      = $self->db;
        my $results = $search->search( 
            fl      => 'id,title,species,object',
            hl      => 0,
            facet   => 0,
            id      => $id,
            params  => $params,
        );

        my $t2 = timer_calc();
        for my $doc ( @{ $results->{'response'}{'docs'} } ) {
            my $cart_id = $db->selectrow_array(
                'select cart_id from cart where user_id=? and doc_id=?', {},
                ( $user_id, $doc->{'id'} )
            );

            if ( $cart_id ) {
                $db->do(
                    q[
                        update   cart
                        set      object=?, species=?, title=?
                    ],
                    {},
                    ( map { $doc->{ $_ } } qw[ object species title ] )
                );
            }
            else {
                $db->do(
                    q[
                        insert
                        into     cart
                                 (user_id, doc_id, object, species, title)
                        values   (?, ?, ?, ?, ?)
                    ],
                    {},
                    ( $user_id, 
                      map { $doc->{ $_ } } qw[ id object species title ] 
                    )
                );
            }

#            $db->do(
#                q[
#                    replace 
#                    into     cart (user_id, doc_id, object, species, title)
#                    values   (?, ?, ?, ?, ?)
#                ],
#                {},
#                ( $user_id, map { $doc->{ $_ } } qw[id object species title] )
#            );

            $change++;
        }
        printf STDERR "added in %s\n", $t2->();
#        for my $doc ( @{ $results->{'response'}{'docs'} } ) {
#            my $info = $store->update(
#                { user_id => $user_id, id => $doc->{'id'} },
#                { '$set'  => $doc },
#                { upsert  => 1, safe => 1 }
#            );
#            $change += $info->{'n'};
#        }
    }
    else {
        if ( $id ) {
            my $rows = $db->do(
                q[
                    delete   
                    from     cart
                    where    user_id=?
                    and      doc_id=?
                ],
                {},
                ( $user_id, $id )
            );

            $change -= $rows;

#            my $info = $store->remove(
#                { user_id => $user_id, id => $id },
#                { safe => 1 }
#            );
#            $change -= $info->{'n'};
        }
    }

    $self->render( json => { change => $change } );
}

# ----------------------------------------------------------------------
sub _get_store {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $client  = MongoDB::MongoClient->new;
    my $db      = $client->get_database('gramene');

    return $db->get_collection('carts');

#    my $carts   = $coll->find({ user_id => $user_id });
#
#    if ( $carts->count == 0 ) {
#        my $id = $coll->insert({
#            user_id => $user_id,
#            items   => {},
#        });
#
#        $carts = $coll->find({ _id => $id });
#    }
#
#    my $cart = $carts->next;
#
#    $cart->{'time'} = $timer->( format => 'seconds' );
#
#    return wantarray ? ( $cart, $coll ) : $cart;
}

1;
