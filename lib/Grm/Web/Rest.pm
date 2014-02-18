package Grm::Web::Rest;

use strict;

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Data::Pageset;
use JSON qw( encode_json decode_json );
use LWP::UserAgent;
use List::Util qw( max );
use List::MoreUtils qw( uniq );
use Mail::Sendmail qw( sendmail );
use Mojo::Util qw( squish trim unquote url_unescape );
use Readonly;

use lib '/usr/local/gramene-40/gramene-lib/lib';
use Grm::Config;
use Grm::Search;
use Grm::DB;
use Grm::Utils qw( 
    camel_case commify iterative_search_values timer_calc pager 
);

Readonly my $URL => '/select?q=text:%s&wt=json';

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
sub cart {
    my $self    = shift;
    my $session = $self->session;
    my $user_id = $session->{'user_id'} || '';
    my $schema  = Grm::DB->new('search')->schema;
    my ($cart)  = $schema->resultset('Cart')->find_or_create(
        { user_id => $user_id }
    );
    my @items   = split( /,/, $cart->value() );

    $self->layout(undef);

    $self->respond_to(
        json => sub {
            $self->render( 
                json => { 
                    items => \@items,
                    count => scalar @items,
                } 
            );
        },

        txt => sub { 
            $self->render( text => Dumper({ items => \@items }) );
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
    my $results     = {};
    my $page_num    = $req->param('page_num') ||  1;
    my $page_size   = $req->param('page_size') 
                   || $web_conf->{'page_size'} 
                   || 10;
    my $orig_params = $req->params . ''; # force stringify
    my $odb         = Grm::Ontology->new;

    my @suggestions;
    if ( $query ) {
        # ensure not multi-valued
        $req->param( query => $query ); 

        #
        # Parse out the request, figure out the "fq" facet queries
        # Create a query string to tack onto the maing "query"
        #
        my $get_url_params = "&rows=$page_size";
        if ( my $fl = $req->param('fl') ) {
            $get_url_params .= "&fl=$fl";
        }

        my $no_hl = $req->param('no_hl');
        unless ( $no_hl ) {
            $get_url_params .= 
              '&hl=true&hl.fl=content&hl.simple.pre=<em>&hl.simple.post=</em>';
        }

        my $no_facet = $req->param('no_facet');
        unless ( $no_facet ) {
            $get_url_params .= '&facet=true&facet.mincount=1' 
                . '&facet.field=species' 
                . '&facet.field=ontology' 
                . '&facet.field=object';
        }

        my $params = $req->params->to_hash;
        my %fq;

        while ( my ( $key, $value ) = each %$params ) {
            next if $key eq 'query'; 
            my @values = ref $value eq 'ARRAY' ? @$value : ( $value );
            if ( $key eq 'fq' ) {
                FQ_VAL:
                for my $fq_val ( @values ) {
                    my ( $facet_name, $facet_val ) 
                        = split( /:/, $fq_val, 2 );

                    if ( defined $facet_val && $facet_val =~ /\w+/ ) {
                        if ( $facet_name eq 'species' ) {
                            if ( lc $facet_val eq 'multi' ) {
                                next FQ_VAL;
                            }

                            $facet_val = lc $facet_val;
                            $facet_val =~ s/\s+/_/g;
                        }

                        push @{ $fq{ $facet_name } }, $facet_val;
                    }
                }
            }
            else {
                for my $v ( @values ) {
                    $get_url_params .= sprintf( '&%s=%s', $key, $v );
                }
            }
        }

        while ( my ( $facet_name, $values ) = each %fq ) {
            for my $val ( @$values ) {
                $get_url_params .= sprintf( 
                    '&fq=%s:%%22%s%%22', 
                    $facet_name, 
                    trim(unquote(url_unescape($val)))
                );
            }
        }

        if ( $page_num > 1 ) {
            $get_url_params .= '&start=' . ($page_num - 1) * $page_size;
        }

        #
        # See if query looks like "chr:start-stop," e.g., 
        # "11 : 14375589-14373565"
        # or
        # "12:17360493...17361111"
        #
        if ( 
            $query =~ /^
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
            my ( $chr, $start, $stop ) = ( $1, $2, $3 );
            my $url_query  = $chr . '%3A' . $start . '-' . $stop;
            my %fq_species = map { lc $_, 1 } @{ $fq{'species'} || [] };
            $self->app->log->info("fq species = ", Dumper(\%fq_species));

            SPECIES:
            for my $ens_species (
                grep { /^ensembl_/ } $gconfig->get('modules')
            ) {
                ( my $species = $ens_species ) =~ s/^ensembl_//;
                if ( %fq_species && !$fq_species{ $species } ) {
                    next SPECIES;
                }

                my $db = Grm::DB->new( $ens_species );
                my ($count) = $db->dbh->selectrow_array(
                    q[
                        select count(*) 
                        from   seq_region 
                        where  name=?
                        and    length>?
                    ],
                    {},
                    ( $chr, $stop )
                );

                next unless $count > 0;

                my $url_species = $db->alias || $species;
                ( my $display = $species ) =~ s/_/ /g;
                push @suggestions, {
                    url => sprintf(
                        'http://ensembl.gramene.org/%s/'.
                        'Location/View?r=%s',
                        ucfirst( $url_species ),
                        $url_query,
                    ),
                    title => sprintf( 
                        'Ensembl %s &quot;%s&quot;</a>',
                        ucfirst( $display ),
                        $query,
                    )
                };
            }
        }
        #
        # Looks legit, so go search Solr
        #
        else {
            if ( ref $page_num eq 'ARRAY' ) {
                $page_num = max( $page_num );
                $req->param( page_num => $page_num );
            }

            my $sconfig  = $gconfig->get('search');
            my $solr_url = $sconfig->{'solr'}{'url'} or die 'No Solr URL';
            my $ua       = LWP::UserAgent->new;

            $ua->agent('GrmSearch/0.1');

            for my $qry ( iterative_search_values( $query ) ) {
                # quote the value if it has a colon as this (e.g., "GO:0001132")
                # has special meaning to Solr (e.g., "species:Zea_mays")
                $qry =~ s/\b(.*[:].*)/%22$1%22/g; 
                $qry =~ s/ /+/g;

                my $get_url = sprintf( $solr_url . $URL, $qry ) 
                            . $get_url_params;

                $self->app->log->debug( "getting '$get_url'" );

                my $res = $ua->request( HTTP::Request->new( GET => $get_url ) );

                if ( $res->is_success ) {
                    $results = decode_json($res->content);
                }
                else {
                    $results = { 
                        code  => $res->code,
                        error => $res->message,
                    };

                    $self->app->log->error( 
                        sprintf(
                            "Problem (%s) query: %s",
                            $res->status_line,
                            $qry,
                        )
                    );
                }

                $self->app->log->debug(
                    "found = ", $results->{'response'}{'numFound'}
                );

                if ( $results->{'response'}{'numFound'} > 0 ) {
                    $query = $qry;
                    last;
                } 
            }

            $results->{'time'} = $timer->( format => 'seconds' );

            my $search_db = Grm::DB->new('search');
            $orig_params  =~ s/query=[^;&]+[;&]?//;

            $search_db->schema->resultset('QueryLog')->create({
                ip        => $session->{'ip'},
                user_id   => $session->{'user_id'},
                num_found => $results->{'response'}{'numFound'} || 0,
                time      => $results->{'time'},
                params    => $orig_params,
                query     => $query,
            });
        }
    }

    $self->respond_to(
        json => sub {
            $self->render( json => $results );
        },

        html => sub { 
            my $pager;
            my $num_found = $results->{'response'}{'numFound'} || 0;
            if ( $num_found > 0 ) {
                my $conf      = Grm::Config->new->get('search');
                my %view_link = %{ $web_conf->{'view'}{'link'} || {} };

                for my $doc ( @{ $results->{'response'}{'docs'} || [] } ) {
                    my $id = $doc->{'id'};
                    if ( 
                        my $hl = $results->{'highlighting'}{ $id }{'content'} 
                    ) {
                        $doc->{'content'} = $hl;
                    }

                    my ( $module, $table, $pk ) = split /\//, $id;
                    $doc->{'url'} = make_web_link(
                        link_conf => \%view_link,
                        module    => $module,
                        table     => $table,
                        id        => $pk,
                    );
                }

                if ( $num_found > $page_size ) {
                    $pager = Data::Pageset->new({
                        total_entries    => $num_found,
                        current_page     => $page_num,
                        entries_per_page => $page_size,
                    });
                }

                my %facets = %{ 
                    $results->{'facet_counts'}{'facet_fields'} || {} 
                };

                for my $facet_name ( grep { !/^ontology$/ } keys %facets ) {
                    my %facet = @{ $facets{ $facet_name } };

                    if ( scalar keys %facet == 1 ) {
                        delete $facets{ $facet_name };
                    }
                }

                my @ontologies = @{ $facets{'ontology'} || [] };
                my %ont_facets;
                while ( my ($term, $count) = splice(@ontologies, 0, 2) ) {
                    ( my $prefix = $term ) =~ s/:.*//;
                    if ( my $term_name = $odb->db->dbh->selectrow_array(
                            'select name from term where term_accession=?',
                            {},
                            $term
                        )
                    ) {
                        $term = sprintf '%s (%s)', $term, $term_name;
                    }

                    push @{ $ont_facets{ $prefix } }, ( $term, $count );
                }

                $facets{'ontology'} = \%ont_facets;

                $results->{'facet_counts'}{'facet_fields'} = \%facets;
            }

            $self->render( 
                session     => $session,
                config      => $web_conf,
                results     => $results,
                pager       => $pager,
                suggestions => \@suggestions,
            );
        },
        
        txt => sub { 
            $self->render( text => Dumper( $results ) );
        },
    );
}

# ----------------------------------------------------------------------
sub search_log {
    my $self      = shift;
    my $req       = $self->req;
    my $order_by  = $req->param('order_by')    || 'date';
    my $page_num  = $req->param('page_num')    || '';
    my $page_size = $self->config('page_size') || 10;
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
    my $query        = $self->param('query')        || '';
    my $term_type_id = $self->param('term_type_id') || '';

    my @terms;
    if ( $query ) {
        my @cols     = qw( term_id name term_accession );
        my $odb      = Grm::Ontology->new;
        my $schema   = $odb->db->schema;
        my @term_ids = $odb->search( 
            query        => $query,
            term_type_id => $term_type_id,
        );

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
                terms        => \@terms,
                query        => $query,
                term_type_id => $term_type_id,
            )
        },

        txt => sub { 
            $self->render( text => Dumper(\@terms) ),
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
    my $self     = shift;
    my $term_id  = $self->param('term_id')        || '';
    my $term_acc = $self->param('term_accession') || '';
    my $odb      = Grm::Ontology->new;

    if ( !$term_id && $term_acc ) {
        my @term_ids = $odb->search( $term_acc );
        $term_id = shift @term_ids;
    }

    my @associations = $term_id 
        ? $odb->get_term_associations( term_id => $term_id )
        : ();

    my $web_conf  = $self->config;
    my %view_link = %{ $web_conf->{'view'}{'link'} || {} };

    for my $assoc ( @associations ) {
        if ( $assoc->{'object_type'} =~ /^GR_(ensembl_(\w+))_(gene)$/ ) {
            my $module          = $1;
            my $ensembl_species = $2;
            my $table           = $3;

            $assoc->{'url'}     = make_web_link(
                link_conf       => \%view_link,
                module          => $module,
                table           => $table,
                ensembl_species => ucfirst $ensembl_species,
                stable_id       => $assoc->{'object_accession_id'},
            );
        }
    }

    $self->layout(undef);

    $self->respond_to(
        json => sub { 
            $self->render( json => { associations => \@associations } ) 
        },

        html => sub { 
            my @species = sort { $a cmp $b } 
                uniq( map { $_->{'object_species'} } @associations ),
            ;

            if ( my $species = lc $self->param('species') ) {
                $species =~ s/_/ /g;
                @associations = 
                    grep { lc $_->{'object_species'} eq $species }
                    @associations
                ;
            }

            $self->render( 
                associations => \@associations,
                species      => \@species,
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
sub make_web_link {
    my %args      = @_;
    my $link_conf = $args{'link_conf'} || {};
    my $module    = $args{'module'}    || '';
    my $table     = $args{'table'}     || '';
    my $id        = $args{'id'}        || '';
    my $doc       = $args{'doc'}       || {};
    my $test      = join '-', $module, $table;
    my $link_tmpl = '';

    for my $key ( sort keys %$link_conf ) {
        if ( $test eq $key || $test =~ /$key/ ) {
            $link_tmpl = $link_conf->{ $key };
            last;
        }
    }

    my $url = '';
    if ( $link_tmpl =~ /^TT:(.+)/ ) {
        my $tt_tmpl = $1;
        my $obj     = {};

        if ( $id ) {
            my $db      = Grm::DB->new( $module );
            my $schema  = $db->schema;
            my $rs_name = camel_case( $table );
            $obj        = $schema->resultset( $rs_name )->find( $id );
        }

        my $tt = Template->new;

        $tt->process( 
            \$tt_tmpl, 
            { 
                object => $obj,
                %args
            }, 
            \$url 
        ) or $url = $tt->error;
    }
    else {
        if ( $module && $table && $id ) {
            $url = "/view/$module/$table/$id";
        }
    }

    return $url;
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
            $self->render( text => Dumper({ items => \@items }) );
        },
    );
}

1;
