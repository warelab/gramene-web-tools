package Grm::Web::Ontology;

use Mojo::Base 'Mojolicious::Controller';
use Cache::Memcached;
use Data::Dump 'dump';
use Grm::DB;
use Grm::Ontology;
use Grm::Utils qw( camel_case commify timer_calc );
use List::Util qw( sum );
use List::MoreUtils qw( uniq );

# ----------------------------------------------------------------------
sub search {
    my $self       = shift;
    my $term_types = $self->get_term_type_counts;

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

# ----------------------------------------------------------------------
sub term {
    my $self     = shift;
    my $id       = $self->param('id');
    my $odb      = Grm::Ontology->new;
    my $schema   = $odb->db->schema;
    my $prefixes = join('|', $odb->get_ontology_accession_prefixes);
    
    my $Term;
    if ( $id =~ /^\d+$/ ) {
        $Term = $schema->resultset('Term')->find($id)
    }
    elsif ( $id =~ /^$prefixes[:]\d+$/ ) {
        ($Term) = $schema->resultset('Term')->search( term_accession => $id );

        if ( !$Term ) {
            my $Syn = $schema->resultset('TermSynonym')->search( 
                term_synonym => $id 
            );

            if ( $Syn ) {
                $Term = $Syn->Term;
            }
        }
    }

    if ( !$Term ) {
        die "Bad term id ($id)";
    }

    my $assocs = $odb->get_term_association_counts( $Term->id );

    $self->layout('default');

    $self->render( 
        term         => $Term,
        associations => $assocs,
        assoc_count  => sum(map { $_->{'count'} } @$assocs),
    );
}

# ----------------------------------------------------------------------
sub association_report {
    my $self    = shift;
    my $term_id = $self->param('term_id') or die 'No term id';
    my $odb     = Grm::DB->new('ontology');
    my $Term    = $odb->schema->resultset('Term')->find($term_id);

    $self->layout('default');
    $self->render( term => $Term );
}
        
# ----------------------------------------------------------------------
sub get_term_type_counts {
    my $self   = shift;
    my $config = $self->config;

    my $cache;
    if (my $cache_server = $config->{'memcached_server'}) {
        $cache = Cache::Memcached->new(servers => [$cache_server]);
    }

    my $odb        = Grm::Ontology->new;
    my $cache_name = join('-', $odb->db->real_name, 'term_types');
    my $term_types = $cache ? $cache->get($cache_name) : undef;

    if ( !$term_types ) {
        my $dbh     = $odb->db->dbh;
        $term_types = $dbh->selectall_arrayref(
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

        if ($cache) {
            eval { $cache->set($cache_name, $term_types) };

            if (my $err = $@) {
                print STDERR "Error loading cache: $err\n";
            }
        }
    }

    return $term_types;
}

1;
