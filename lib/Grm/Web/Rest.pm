package Grm::Web::Rest;

use strict;

use Mojo::Base 'Mojolicious::Controller';

use Data::Dump 'dump';
use Data::Pageset;
use Grm::Config;
use Grm::DB;
use Grm::Search;
use Grm::Utils qw(camel_case commify iterative_search_values timer_calc);
use JSON qw(encode_json decode_json);
use LWP::UserAgent;
use List::MoreUtils qw(uniq);
use List::Util qw(max sum);
use Mail::Sendmail qw(sendmail);
use Mojo::Util qw(squish trim unquote url_unescape);

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
            $self->render( text => dump({ actions => \@actions }) );
        },
    );
}

# ----------------------------------------------------------------------
sub search {
    my $self        = shift;
    my $session     = $self->session;
    my $req         = $self->req;
    my $query       = squish(trim(url_unescape($req->param('query') || '')));
    my $web_conf    = $self->config;
    my $gconfig     = Grm::Config->new;
    my $search      = Grm::Search->new;
    my $timer       = timer_calc();
    my $page_num    = $req->param('page_num') ||  1;
    my $page_size   = $req->param('page_size') 
                   || $web_conf->{'page_size'} 
                   || 10;
    my $odb         = Grm::Ontology->new;
    my $results     = {};

    if ($query) {
        # ensure not multi-valued
        $req->param( query => $query ); 

        $results   = $search->search(
            query  => $query,
            params => $req->params->to_hash,
            core   => $req->param('core')      // '',
            fl     => $req->param('fl')        // '',
            hl     => defined $req->param('no_hl') ? $req->param('no_hl') : 1,
            no_facet  => $req->param('no_facet')  //  1,
            page_size => $req->param('page_size') 
                      || $web_conf->{'page_size'} 
                      || 10,
        );

        #
        # The presence of suggestions means it didn't look like
        # a good query, e.g., "chr:start-stop"
        #
        if ( !$results->{'suggestions'} ) {
            #
            # Force stringify, store the "query" separately
            #
            (my $orig_params = $req->params . '') =~ s/query=[^;&]+[;&]?//;

            my $search_db = Grm::DB->new('search');
            $search_db->schema->resultset('QueryLog')->create({
                ip        => $session->{'ip'},
                user_id   => $session->{'user_id'},
                num_found => $results->{'num_found'} || 0,
                time      => $results->{'time'},
                params    => $orig_params,
                query     => $query,
            });
        }
    }

    #
    # Here we clean up the Solr results just a touch
    #
    if (my $num_found = $results->{'response'}{'numFound'}) {
        for my $doc ( @{ $results->{'response'}{'docs'} || [] } ) {
            my $id = $doc->{'id'};
            if (my $hl = $results->{'highlighting'}{ $id }{'text'}) {
                if (ref $hl eq 'ARRAY') {
                    $hl = join(' ', @$hl);
                }
                $doc->{'content'} = $hl;
            }

            $doc->{'content'} ||= $doc->{'description'};
        }

        if ( $num_found > $page_size ) {
            my $pager = Data::Pageset->new({
                total_entries    => $num_found,
                current_page     => $page_num,
                entries_per_page => $page_size,
                mode             => 'slide',
            });

            $results->{'pager'} = {
                total_entries => $num_found,
                current_page  => $page_num,
                pages         => [
                    map {{ 
                        page    => $_,
                        current => $_ == $page_num,
                    }}
                    @{$pager->pages_in_set},
                ],
            };
        }

        my %facets;
        while (my ($facet_category, $facets) = 
            each %{ $results->{'facet_counts'}{'facet_fields'} || {} }
        ) {
            next if scalar @$facets == 2; # only one item (eg, "foo = 1")

            while ( my ($facet_name, $count) = splice(@$facets, 0, 2) ) {
                (my $display = ucfirst $facet_name) =~ s/_/ /g;
                (my $cat = ucfirst $facet_category) =~ s/_/ /g;

                if ($facet_category eq 'ontology') {
                    # 
                    # Use term prefix ("GO") for category name
                    # 
                    ($cat = $facet_name) =~ s/:.*//; 

                    if ( my $term_name = $odb->db->dbh->selectrow_array(
                            'select name from term where term_accession=?',
                            {},
                            $facet_name
                        )
                    ) {
                        $display = sprintf '%s (%s)', $facet_name, $term_name;
                    }
                }

                push @{ $facets{ $cat } }, { 
                    name    => $facet_category,
                    value   => $facet_name,
                    display => $display, 
                    count   => $count 
                };
            }
        }

        $results->{'facet_counts'} = \%facets;
        delete $results->{'highlighting'}
    }

    $self->respond_to(
        json => sub {
            $self->render( json => $results );
        },

        html => sub { 
            $self->render( 
                session => $session,
                config  => $web_conf,
                results => $results,
            );
        },
        
        txt => sub { 
            $self->render( text => dump( $results ) );
        },
    );
}

# ----------------------------------------------------------------------
sub search_log {
    my $self      = shift;
    my $req       = $self->req;
    my $order_by  = $req->param('order_by')      || 'date';
    my $page_num  = $req->param('page_num')      || '';
    my $page_size = $self->config->{'page_size'} || 10;
    my $db        = Grm::DB->new('search');
    my %args      = ( order_by => { -asc => $order_by } );

    if ( $self->accepts('html') || $page_num ) {
        $page_num     ||= 1;
        $args{'page'}   = $page_num;
        $args{'rows'}   = $page_size;
        $args{'offset'} = ( $page_num - 1 ) * $page_size;
    }

    my $queries = $db->schema->resultset('QueryLog')->search_rs(
        undef, \%args 
    );

    $queries->result_class('DBIx::Class::ResultClass::HashRefInflator');

    $self->layout(undef);

    $self->respond_to(
        json => sub {
            my %data;
            if ( $self->param('format') eq 'dt' ) {
                my @data;
                if ( $queries->count > 0 ) {
                    my @cols = qw( query num_found params user_id ip time date );
                    while ( my $qry = $queries->next ) {
                        push @data, [ map { $qry->{ $_ } } @cols ];
                    }

                    %data = ( aaData => \@data );
                }

                %data = ( aaData => \@data );
            }
            else {
                %data = ( $queries => [ $queries->all ] );
            }

            $self->render( json => \%data );
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

# ----------------------------------------------------------------------
sub ontology_search {
    my $self         = shift;
    my $query        = $self->param('oquery')       || '';
    my $term_type_id = $self->param('term_type_id') || '';
    my $num_found    = 0;
    my $show_pager   = 0;

    my ($pager, @terms);
    if ( $query ) {
        my @cols     = qw( term_id name term_accession );
        my $odb      = Grm::Ontology->new;

        my @term_ids = $odb->search( 
            query        => $query,
            term_type_id => $term_type_id,
        );

        $num_found    = scalar @term_ids;
#        my $web_conf  = $self->config;
#        my $page_size = $self->param('page_size') 
#                     || $web_conf->{'page_size'} 
#                     || 10;
#
#        my $current_page = $self->param('page_num') || 1;
#        $pager = Data::Pageset->new({
#            total_entries    => $num_found,
#            current_page     => $current_page,
#            entries_per_page => $page_size,
#        });
#
#        if ( $num_found > $page_size ) {
#            @term_ids = splice( @term_ids, $pager->first - 1, $page_size );
#            $show_pager = 1;
#        }

        my $schema = $odb->db->schema;
        for my $term_id ( @term_ids ) {
            my $Term = $schema->resultset('Term')->find( $term_id );
            push @terms, { map { $_, $Term->$_() } @cols };
        }
    }

    $self->layout(undef);

    $self->respond_to(
        json => sub { 
            $self->render( json => { terms => \@terms } ) 
        },

        html => sub {
            $self->render( 
                num_found    => $num_found,
                terms        => \@terms,
                query        => $query,
                term_type_id => $term_type_id,
                pager        => $pager,
                show_pager   => $show_pager,
            );
        },

        txt => sub { 
            $self->render( text => dump(\@terms) ),
        },

        tab  => sub { 
            if ( @terms > 0 ) {
                my $tab  = "\t";
                my @cols = sort keys %{ $terms[0] };
                my @data;
                push @data, join( $tab, @cols );
                for my $term ( @terms ) {
                    push @data, join( $tab, map { $term->{ $_ } } @cols );
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
sub ontology_associations {
    my $self         = shift;
    my $term_id      = $self->param('term_id') || '';
    my $odb          = Grm::Ontology->new;
    my @associations = $odb->get_term_associations(
        term_id      => $term_id, 
        species_id   => $self->param('species_id')  ||  0,
        species      => $self->param('species')     || '',
        object_type  => $self->param('object_type') || '',
    );

    my $species_count = $odb->get_term_association_counts($term_id);
#    my %species_count;
#    for my $assoc (@associations) {
#        if (my $sp = $assoc->{'species'}) {
#            $species_count{$sp}{'species_id'} = $sp->{'species_id'};
#            $species_count{$sp}{'count'}++;
#        }
#    }

    $self->respond_to(
        json => sub {
            $self->render(
                json => { 
                    term_id       => $term_id, 
                    associations  => \@associations,
                    species_count => $species_count,
                }
            );
        },

        txt  => sub { $self->render( text => dump(\@associations) ) },

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
sub view_cart {
    my $self  = shift;
    my @items = ();

    for my $item ( split( /\s*,\s*/, $self->param('cart') || '' ) ) {
        my ( $module, $table, $id ) = split( /\//, $item );
        next unless $module && $table && $id;

        push @items, { 
            module => $module,
            table  => $table,
            id     => $id,
            hit_id => $item 
        };
    }

    $self->layout(undef);

    $self->respond_to(
        json => sub {
            $self->render( json => { items => \@items } );
        },

        html => sub { 
            $self->render( items => \@items );
        },

        txt => sub { 
            $self->render( text => dump({ items => \@items }) );
        },
    );
}

1;
