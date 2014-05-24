package Grm::Web::Search;

use Mojo::Base 'Mojolicious::Controller';
use Mojolicious::Sessions;
use Digest::MD5;
use Data::Dumper;
use Grm::DB;
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

# ----------------------------------------------------------------------
sub cloud {
    my $self  = shift;
    my $db    = Grm::DB->new('search');
    my %words = ();

    for my $query (
        @{ $db->dbh->selectcol_arrayref('select query from query_log') }
    ) {
        if ( $query =~ /^
                ([\w.-]+)        # seq_region name (chr, scaffold)
                \s*              # maybe space
                :                # literal colon
                \s*              # maybe space
                ([\d,]+)         # start
                \s*              # maybe space
                (?:\.{2,3}|[-])  # either ellipses (2 or 3) or dash
                \s*              # maybe space
                ([\d,]+)         # stop
            $/xms 
        ) {
            next;
        }
        $query =~ s/\*//g;
        $query =~ s/%22//g;
        $query =~ s/\+/ /g;

        $words{ $query }++;
    }

    my @words;
    while ( my ( $word, $count ) = each %words ) {
        if ( $count > 1 ) {
            for ( 1 .. $count ) {
                push @words, qq["$word"];
            }
        }
    }

    $self->layout('default');

    $self->render( words => \@words );
}

# ----------------------------------------------------------------------
sub search {
    my $self = shift;
    my $ip   = $self->req->headers->header('X-Forwarded-For');
    my $id   = $self->session('user_id') || make_id( $ip );

    $self->session( ip => $ip );

    $self->session( user_id => $id );

    $self->layout('default');

    $self->render( session => $self->session );
}

# ----------------------------------------------------------------------
sub log {
    my $self      = shift;
    my $req       = $self->req;

    $self->layout('default');

    $self->render( config => $self->config );
}

# ----------------------------------------------------------------------
sub make_id {
    my ( $c, $ip ) = @_;
    my $md5  = Digest::MD5->new;
    my $id   = $md5->md5_base64( time, $$, $ip, int(rand(10)) );

    $id =~ tr|+/=|-_.|;  # Make non-word chars URL-friendly

    return $id;
}

1;
