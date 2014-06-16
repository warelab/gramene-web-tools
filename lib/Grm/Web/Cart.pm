package Grm::Web::Cart;

use Data::Dumper;
use File::Basename qw( basename );
use File::Copy qw( move );
use File::Path qw( mkpath );
use File::Spec::Functions;
use File::Temp qw( tempfile );
use Grm::DB;
use Grm::Search;
use Grm::Utils qw( timer_calc );
use JSON::XS qw( encode_json decode_json );
use IO::Compress::Gzip qw( gzip $GzipError );
use List::MoreUtils qw( uniq );
use Mojo::Base 'Mojolicious::Controller';
use MongoDB;
use Perl6::Slurp qw( slurp );

# ----------------------------------------------------------------------
sub download {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $coll    = $self->_get_store();
    my $rec     = $coll->find({ user_id => $user_id })->next;
    my $cart    = $rec->{'items'} ? $rec->{'items'} : {};

    my $download_dir = $self->app->home->rel_file('public/tmp');
    if ( !-d $download_dir ) {
        mkpath $download_dir;
    }

    my ( $fh, $filename ) = tempfile( 'cartXXXXXX', DIR => $download_dir );
    print $fh join( "\t", qw[ species object title ] ), "\n";

    while ( my ( $doc_id, $doc ) = each %$cart ) {
        my ( $module, $table, $pk ) = split( /\//, $doc_id );
        print $fh 
            join( "\t", map { $doc->{ $_ } } qw[ species object title ] ),
            "\n";
    }
    close $fh;

    my $gzipped = $filename . '.txt.gz'; # tempfile doesn't allow suffixes
    my $status  = gzip $filename => $gzipped or die "gzip failed: $GzipError\n";
    unlink $filename;

    $self->render( json => { filename => basename($gzipped) } );
}

# ----------------------------------------------------------------------
sub view {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $coll    = $self->_get_store();

    $self->layout('default');

    $self->respond_to(
        json => sub { 
            my $rec   = $coll->find({ user_id => $user_id })->next;
            my $cart  = $rec->{'items'} ? $rec->{'items'} : {};
            my %count = ();
            my $total = 0;
            while ( my ( $doc_id, $doc ) = each %$cart ) {
                $count{ $doc->{'species'} || 'N/A' }{ $doc->{'object'} }++;
                $total++;
            }

            my @counts;
            for my $species ( keys %count ) {
                while ( my ($object, $count) = each %{ $count{ $species } } ) {
                    push @counts, {
                        species => $species,
                        object  => $object,
                        count   => $count,
                    }
                }
            }

            $self->render( json => { total => $total, summary => \@counts } );
        },

        html => sub { 
            $self->render();
        },

        txt => sub { 
            my $rec   = $coll->find({ user_id => $user_id })->next;
            my $cart  = $rec->{'items'} ? $rec->{'items'} : {};
            my ( @out, @cols );
            while ( my ( $doc_id, $doc ) = each %$cart ) {
                if ( !@cols ) {
                    @cols = keys %$doc;
                    push @out, join( "\t", @cols );
                }

                push @out, join( "\t", map { $doc->{$_} } @cols );
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
    my $coll    = $self->_get_store();
    my $rec     = $coll->find({ user_id => $user_id })->next;
    my $count   = ref $rec eq 'HASH' ? $rec->{'count'} : 0;

    $self->render( json => { count => $count } );
}

# ----------------------------------------------------------------------
sub empty {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $coll    = $self->_get_store();

    $coll->remove({ user_id => $user_id });

    $self->render( json => { count => 0 } );
}

# ----------------------------------------------------------------------
sub edit {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $req     = $self->req;
    my $params  = $req->params->to_hash;
    my $action  = lc $self->param('action') || 'add';
    my @ids     = split( /\s*,\s*/, $self->param('id')   || '' );
    my @types   = (
        map { [ split( /:/, $_ ) ] } 
        split( /\s*,\s*/, $self->param('type') || '' )
    );

    my $coll  = $self->_get_store();
    my $rec   = $coll->find({ user_id => $user_id })->next;
    my $cart  = $rec->{'items'} ? $rec->{'items'} : {};

    if ( $action eq 'add' ) {
        if ( !@ids ) { @ids = ('') } # at least one

        for my $id ( @ids ) {
            my $search  = Grm::Search->new;
            my $results = $search->search( 
                fl      => 'id,title,species,object',
                hl      => 0,
                facet   => 0,
                id      => $id,
                params  => $params,
            );

            for my $doc ( @{ $results->{'response'}{'docs'} } ) {
                $cart->{ $doc->{'id'} } = $doc;
            }
        }
    }
    else {
        if ( @ids ) {
            map { delete $cart->{ $_ } } @ids;
        }
        elsif ( @types ) {
            DOC:
            while ( my ( $doc_id, $doc ) = each %$cart ) {
                for my $type ( @types ) {
                    my ( $object, $species ) = @$type;
                    next if $doc->{'object'} ne $object;
                    next if $doc->{'species'} 
                        && ($doc->{'species'} eq $species);

                    delete $cart->{ $doc_id };
                    next DOC;
                }
            }
        }
    }

    my $count = scalar keys %{ $cart } || 0;

    if ( $count > 0 ) {
        $coll->update(
            { user_id => $user_id },
            { '$set'  => { items => $cart, count => $count } },
            { upsert  => 1 }
        );
    }
    else {
        $coll->remove({ user_id => $user_id });
    }

    $self->render( json => { count => $count } );
}

# ----------------------------------------------------------------------
sub _get_store {
    my $self    = shift;
    my $client  = MongoDB::MongoClient->new;
    my $db      = $client->get_database('gramene');

    return $db->get_collection('carts');
}
