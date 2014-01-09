package Grm::Web::Ontology;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-40/gramene-lib/lib';
use Grm::DB;
use Grm::Ontology;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );
use List::MoreUtils qw( uniq );

# ----------------------------------------------------------------------
sub search {
    my $self   = shift;
    my $query  = $self->param('query') || '';
    my $odb    = Grm::Ontology->new;
    my $dbh    = $odb->db->dbh;

    # to-do: cache this
    my $term_types = $dbh->selectall_arrayref(
        q[
            select   tt.term_type_id, 
                     tt.prefix, 
                     tt.term_type, 
                     count(t.term_id) as num_terms
            from     term_type tt, term t
            where    tt.prefix is not null
            and      t.term_type_id=tt.term_type_id
            group by 1,2
            order by 1,2
        ],
        { Columns => {} }
    );


    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { term_types => $term_types } );
        },
        html => sub { 
            $self->render( 
                title      => 'Ontology Search',
                term_types => $term_types,
            );
        },
        txt => sub { 
            $self->render( text => Dumper({ term_types => $term_types }) );
        },
    );
}

1;
