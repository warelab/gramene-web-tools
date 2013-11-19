package Grm::Web::Rest;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use Mail::Sendmail qw( sendmail );

use lib '/usr/local/gramene-lib/lib';
use Grm::Config;
use Grm::Search;
use Grm::Utils qw( 
    camel_case commify iterative_search_values timer_calc pager 
);
use LWP::UserAgent;
use Readonly;
use JSON qw( encode_json decode_json );

Readonly my $URL => join( '',
    'http://brie.cshl.edu:8983/solr/grm-search/select?',
    'q=%s&wt=json&hl=true&hl.fl=*'
);

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
    my $self    = shift;
    my $req     = $self->req;
    my $query   = $req->param('query') || '';
    my $search  = Grm::Search->new;
    my $timer   = timer_calc();
    my $results = {};
    my $ua      = LWP::UserAgent->new;
    $ua->agent('GrmSearch/0.1');

    if ( $query ) {
        my $db       = $req->param('db')       || '';
        my $category = $req->param('category') || '';
        my $taxonomy = $req->param('taxonomy') || '';

        for my $t ( iterative_search_values( $query ) ) {
            my $req = HTTP::Request->new( GET => sprintf( $URL, $query ) );
            my $res = $ua->request($req);

            # Check the outcome of the response
            if ( $res->is_success ) {
                $results = decode_json($res->content);

                last if $res->{'response'}{'numFound'} > 0;
            }
            else {
                $results = { 
                    code  => $res->code,
                    error => $res->message,
                };

                report_error( sprintf(
                    "Problem querying %s for '%s': %s",
                    $URL,
                    $query,
                    $res->status_line,
                ));

                last;
            }
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

            my $pager  = pager(
                count            => $results->{'response'}{'numFound'},
                current_page     => $req->param('page_num'),
                url              => $self->url_for('/rest/search'),
                form_action      => $form_action,
                click_action     => $form_action,
                entries_per_page => 25,
            );
print STDERR "pager = ", Dumper($pager), "\n";

            my $conf   = Grm::Config->new->get('search');
            my $list_cols = $conf->{'list_columns'};

            for my $doc ( @{ $results->{'response'}{'docs'} || [] } ) {
                my $id = $doc->{'id'};
                if ( my $hl = $results->{'highlighting'}{ $id }{'content'} ) {
                    $doc->{'content'} = $hl;
                }
            }

            $self->render( 
                results => $results,
#                pager   => $pager,
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
