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
    my $self         = shift;
    my $term_id      = $self->param('term_id') or die 'No term id';
    my $odb          = Grm::Ontology->new;
    my @associations = $odb->get_term_associations(
        term_id      => $term_id, 
        species_id   => $self->param('species_id') || 0,
    );

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render(
                json => { term_id => $term_id, associations => \@associations }
            );
        },

        html => sub { 
            my (%count_by_species, %assoc_by_type);

            if (scalar @associations > 0) {
                my $web_conf  = $self->config;
                my %view_link = %{ $web_conf->{'view'}{'link'} || {} };

                for my $assoc ( @associations ) {
                    if ( $assoc->{'object_type'} eq 'gene' ) {
                        ( my $species = lc $assoc->{'species'} ) =~ s/ /_/g;

#                        $assoc->{'url'}     = $self->make_web_link(
#                            link_conf       => \%view_link,
#                            module          => 'ensembl_' . $species,
#                            table           => 'gene',
#                            ensembl_species => ucfirst $species,
#                            stable_id       => $assoc->{'object_accession_id'},
#                        );
                    }

                    push @{ $assoc_by_type{$assoc->{'species'}} }, $assoc;
                    $count_by_species{ $assoc->{'species'} }++;
                }
            }

            $self->render( 
                associations => \@associations,
                species_list => \%count_by_species,
                term         => 
                    $odb->db->schema->resultset('Term')->find($term_id),
            );
        },

        txt  => sub { $self->render( text => Dumper(\@associations) ) },

        tab  => sub { 
            if ( @associations > 0 ) {
                my $tab  = "\t";
                my @cols = sort keys %{ $associations[0] };
                my @data;
                push @data, join( $tab, @cols );
                for my $assoc ( @associations ) {
                    push @data, join( $tab, map { $assoc->{ $_ } } @cols );
                }

                $self->render( text => join( "\n", @data ) );
            }
            else {
                $self->render( text => 'None' );
            }
        },
    );
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
