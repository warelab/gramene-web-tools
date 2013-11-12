package Grm::Web::Search;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-lib/lib';
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

# This action will render a template
sub search {
    my $self   = shift;
    my $search = Grm::Search->new;
#    my $timer  = timer_calc();
    my $req    = $self->req;
    my $query  = $req->param('query') || '';
    my $res    = {};

    if ( $query ) {
        my $format   = $req->param('fmt')      || 'json';
        my $db       = $req->param('db')       || '';
        my $category = $req->param('category') || '';
        my $taxonomy = $req->param('taxonomy') || '';

        for my $t ( iterative_search_values( $query ) ) {
#            $res         =  $search->search_mysql(
#                query    => $t, 
#                category => $category,
#                taxonomy => $taxonomy,
#                db       => $db,
#            );
#
#            last if $res->{'num_hits'} > 0;
        }

#        $res->{'time'} = $timer->();
    }

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => $res );
        },
        html => sub { 
            $self->render( 
                results => $res,
                query   => $query,
            );
        },
        txt => sub { 
            $self->render( text => Dumper($res) );
        },
    );
}

1;
