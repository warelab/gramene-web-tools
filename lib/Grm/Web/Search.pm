package Grm::Web::Search;

use Mojo::Base 'Mojolicious::Controller';
use Mojolicious::Sessions;
use Digest::MD5;
use Data::Dumper;
use Grm::DB;
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

sub search {
    my $self = shift;
    my $ip   = $self->req->headers->header('X-Forwarded-For');
    my $id   = $self->session('user_id') || make_id( $ip );

    $self->session( ip => $ip );

    $self->session( user_id => $id );

    $self->layout('default');

    $self->render( session => $self->session );
}

sub log {
    my $self      = shift;
    my $req       = $self->req;
    my $order_by  = $req->param('order_by')    || 'date';
    my $page_num  = $req->param('page_num')    || 1;
    my $page_size = $self->config('page_size') || 10;
    my $db        = Grm::DB->new('search');
    my %args      = ( order_by => { -asc => $order_by } );

    if ( $self->accepts('html') ) {
        $args{'page'}   = $page_num;
        $args{'rows'}   = $page_size;
        $args{'offset'} = ( $page_num - 1 ) * $page_size;
    }

    my $queries = $db->schema->resultset('QueryLog')->search_rs(
        undef, \%args 
    );

    $queries->result_class('DBIx::Class::ResultClass::HashRefInflator');

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { queries => [ $queries->all ] } );
        },

        html => sub { 
            $self->render( queries => $queries );
        },

        tab  => sub { 
            if ( $queries->count > 0 ) {
                my $rs   = $queries->result_source;
                my @cols = $rs->columns;
                my $tab  = "\t";
                my @data = ();
                push @data, join( $tab, @cols );
                while ( my $qry = $queries->next ) {
                    push @data, join( $tab, map { $qry->{ $_ } } @cols );
                }

                $self->render( text => join( "\n", @data ) );
            }
            else {
                $self->render( text => 'None' );
            }

        },
    );
}

sub make_id {
    my ( $c, $ip ) = @_;
    my $md5  = Digest::MD5->new;
    my $id   = $md5->md5_base64( time, $$, $ip, int(rand(10)) );

    $id =~ tr|+/=|-_.|;  # Make non-word chars URL-friendly

    return $id;
}

1;
