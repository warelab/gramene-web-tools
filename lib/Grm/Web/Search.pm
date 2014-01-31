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

    $self->layout('default');

    $self->render( config => $self->config );
}

sub make_id {
    my ( $c, $ip ) = @_;
    my $md5  = Digest::MD5->new;
    my $id   = $md5->md5_base64( time, $$, $ip, int(rand(10)) );

    $id =~ tr|+/=|-_.|;  # Make non-word chars URL-friendly

    return $id;
}

1;
