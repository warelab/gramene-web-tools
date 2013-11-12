package Grm::Web::Rest;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-lib/lib';
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );
use LWP::Simple qw( get );
use Readonly;
use JSON qw( encode_json decode_json );

Readonly my $URL => 
    'http://brie.cshl.edu:8983/solr/grm-search/select?q=%s&wt=json';

# ----------------------------------------------------------------------
sub info {
    my $self = shift;

    my @actions = qw( search ontology markers );

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { actions => \@actions } );
        },

        html => sub { 
            $self->render( actions => \@actions );
        },

        txt => sub { 
            $self->render( text => Dumper({ actions => \@actions }) );
        },
    );
}

# ----------------------------------------------------------------------
sub search {
    my $self   = shift;
    my $search = Grm::Search->new;
    my $timer  = timer_calc();
    my $req    = $self->req;
    my $res    = {};

    if ( my $query = $req->param('query') ) {
        my $db       = $req->param('db')       || '';
        my $category = $req->param('category') || '';
        my $taxonomy = $req->param('taxonomy') || '';

        for my $t ( iterative_search_values( $query ) ) {
            $res = decode_json(get(sprintf($URL, $query)));

            last if $res->{'response'}{'numFound'} > 0;

#            $res         =  $search->search_mysql(
#                query    => $t, 
#                category => $category,
#                taxonomy => $taxonomy,
#                db       => $db,
#            );
#
#            last if $res->{'num_hits'} > 0;
        }

        $res->{'time'} = $timer->();
    }

    $self->respond_to(
        json => sub {
            $self->render( json => $res );
        },
        html => sub { 
            $self->render( results => $res );
        },
        txt => sub { 
            $self->render( text => Dumper($res) );
        },
    );
}

1;
