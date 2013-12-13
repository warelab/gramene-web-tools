package Grm::Web::Rest;

use strict;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw( squish trim unquote url_unescape );
use Data::Dumper;
use Mail::Sendmail qw( sendmail );
use Data::Pageset;

use lib '/usr/local/gramene-lib/lib';
use Grm::Config;
use Grm::Search;
use Grm::Utils qw( 
    camel_case commify iterative_search_values timer_calc pager 
);
use LWP::UserAgent;
use Readonly;
use JSON qw( encode_json decode_json );

Readonly my $URL => '/select?q=text:%%22%s%%22&wt=json&hl=true&hl.fl=content' .
    '&hl.simple.pre=<em>&hl.simple.post=</em>' .
    '&facet=true&facet.mincount=1' .
    '&facet.field=species' .
    '&facet.field=ontology' .
    '&facet.field=object';
#    '&facet.pivot=species_name,object_type';

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
    my $self      = shift;
    my $req       = $self->req;
    my $query     = squish($req->param('query') || '');
    my $web_conf  = $self->config;
    my $config    = Grm::Config->new->get('search');
    my $solr_url  = $config->{'solr'}{'url'} or die 'No Solr URL';
    my $search    = Grm::Search->new;
    my $timer     = timer_calc();
    my $results   = {};
    my $ua        = LWP::UserAgent->new;
    my $page_size = $web_conf->{'page_size'};

    $ua->agent('GrmSearch/0.1');

    if ( $query ) {
        $query =~ s/ /+/g;
        my $get_url = sprintf( $solr_url . $URL, $query );
        my $params = $req->params->to_hash;
        #print STDERR "params = ", Dumper($params), "\n";
        my %fq;
        while ( my ( $key, $value ) = each %$params ) {
            next if $key eq 'query';
            my @values = ref $value eq 'ARRAY' ? @$value : ( $value );
            if ( $key eq 'fq' ) {
                for my $fq_val ( @values ) {
                    my ( $facet_name, $facet_val ) = split( /=/, $fq_val );
                    if ( defined $facet_val && $facet_val =~ /\w+/ ) {
                        push @{ $fq{ $facet_name } }, $facet_val;
                    }
                }
            }
            else {
                for my $v ( @values ) {
                    $get_url .= sprintf( '&%s=%s', $key, $v );
                }
            }
        }

        while ( my ( $facet_name, $values ) = each %fq ) {
            for my $val ( @$values ) {
                $get_url .= sprintf( 
                    '&fq=%s:%%22%s%%22', 
                    $facet_name, 
                    trim(unquote(url_unescape($val)))
                );
            }

#                if ( scalar @$values > 1 ) {
#                    $get_url .= sprintf( '&fq=%s%%3D(%s)',
#                        $facet_name, 
#                        join( '+OR+', @$values )
#                    );
#                }
#                else {
#                    $get_url .= sprintf( '&fq=%s%%3D%s', 
#                        $facet_name, $values->[0] 
#                    );
#                }
        }

        $get_url .= '&rows=' . $page_size;

        my $page_num = $req->param('page_num');
        if ( $page_num > 1 ) {
            $get_url .= '&start=' . ($page_num - 1) * $page_size;
        }

        print STDERR "getting '$get_url'\n";

        #my @ens_hits = $search->_search_ensembl( $query );
        #print STDERR "ens = ", Dumper(\@ens_hits), "\n";

        my $req = HTTP::Request->new( GET => $get_url );
        my $res = $ua->request($req);

        if ( $res->is_success ) {
            $results = decode_json($res->content);
        }
        else {
            $results = { 
                code  => $res->code,
                error => $res->message,
            };

#                report_error( sprintf(
#                    "Problem querying %s for '%s': %s",
#                    $URL,
#                    $query,
#                    $res->status_line,
#                ));
        }

        $results->{'time'} = $timer->();
    }

    $self->respond_to(
        json => sub {
            $self->render( json => $results );
        },
        html => sub { 
#            my $res = WebService::Solr::Response->new($resul);
#            for my $doc ( $res->docs ) {
#                print $doc->value_for('id'), "\n";
#            }
#            my $pager = $res->pager;
            my $form_action = sprintf( q['javascript:get_page("%s")'], $query );

#            my $pager  = pager(
#                count            => $results->{'response'}{'numFound'},
#                current_page     => $req->param('page_num'),
#                url              => $self->url_for('/rest/search'),
#                form_action      => $form_action,
#                click_action     => $form_action,
#                entries_per_page => 25,
#            );
#
            my $pager;
            my $num_found = $results->{'response'}{'numFound'} || 0;
            if ( $num_found > 0 ) {
                my $conf      = Grm::Config->new->get('search');
                my $list_cols = $conf->{'list_columns'};
                my %view_link = %{ $web_conf->{'view'}{'link'} || {} };

                for my $doc ( @{ $results->{'response'}{'docs'} || [] } ) {
                    my $id = $doc->{'id'};
                    if ( 
                        my $hl = $results->{'highlighting'}{ $id }{'content'} 
                    ) {
                        $doc->{'content'} = $hl;
                    }

                    my ( $module, $table, $pk ) = split /\//, $id;
                    my $test  = join '-', $module, $table;

                    my $link_tmpl = '';
                    for my $key ( %view_link ) {
                        if ( $test eq $key || $test =~ /$key/ ) {
                            $link_tmpl = $view_link{ $key };
                            last;
                        }
                    }

                    if ( $link_tmpl =~ /^TT:(.+)/ ) {
                        my $tt_tmpl = $1;
                        my $db      = Grm::DB->new( $module );
                        my $schema  = $db->schema;
                        my $rs_name = camel_case( $table );
                        my $obj     = $schema->resultset( $rs_name )->find( $pk );
                        my $tt      = Template->new;
                        my $tmp;
                        $tt->process( 
                            \$tt_tmpl, 
                            { hit => $doc, object => $obj }, 
                            \$tmp 
                        ) or $tmp = $tt->error;

                        $doc->{'url'} = $tmp;
                    }
                }

                if ( $num_found > $page_size ) {
                    $pager = Data::Pageset->new({
                        total_entries    => $num_found,
                        current_page     => $req->param('page_num') || 1,
                        entries_per_page => 
                            scalar @{ $results->{'response'}{'docs'} },
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
                    push @{ $ont_facets{ $prefix } }, ( $term, $count );
                }
                $facets{'ontology'} = \%ont_facets;

                $results->{'facet_counts'}{'facet_fields'} = \%facets;
            }

            $self->render( 
                config  => $web_conf,
                results => $results,
                pager   => $pager,
            );
        },
        txt => sub { 
            $self->render( text => Dumper( $results ) );
        },
    );
}

# ----------------------------------------------------------------------
sub report_error {
    if ( my $err = shift ) {
        sendmail(
            To      => 'kclark@cshl.edu',
            From    => 'webserver@gramene.org',
            Subject => 'Web Server Error',
            Message => $err,
        );
    }
}

1;
