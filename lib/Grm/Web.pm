package Grm::Web;

use Data::Dump 'dump';
use File::Spec::Functions;
use Grm::Utils qw( camel_case );
use Mojo::Base 'Mojolicious';
use Mojo::Log;

sub startup {
    my $self = shift;

    $self->plugin('tt_renderer');

    $self->plugin('yaml_config', { 
        file => $self->home->rel_file('conf/grm-web.yaml')
    });


    $self->log( 
        Mojo::Log->new(
            path  => $self->home->rel_file('logs/mojo.log'),
            level => $self->config('log_level') || 'info',
        )
    );

    if ( my $secret = $self->config('secret') ) {
        $self->secrets([ $secret ]);
    }

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');

    $self->sessions->default_expiration(86400);

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/')->to('root#home');

    $r->any('/cart/edit')->to('cart#edit');

    $r->any('/cart/download')->to('cart#download');

    $r->any('/cart/count')->to('cart#count');

    $r->post('/cart/empty')->to('cart#empty');

    $r->get('/cart/view')->to('cart#view');

    $r->get('/feedback')->to('feedback#form');

    $r->post('/feedback/submit')->to('feedback#submit');
    
    $r->get('/feedback')->to('feedback#form');

    $r->post('/feedback/submit')->to('feedback#submit');
    
    $r->get('/search')->to('search#search');

    $r->get('/search/cloud')->to('search#cloud');

    $r->get('/search/log')->to('search#log');

    $r->any('/download/package')->to('download#package');

    $r->get('/rest')->to('rest#info');

    $r->get('/rest/info')->to('rest#info');

    $r->get('/rest/search')->to('rest#search');

    $r->get('/rest/search_log')->to('rest#search_log');

    $r->get('/rest/ontology_search')->to('rest#ontology_search');

    $r->get('/ontology/association_report/:term_id')->to(
        'ontology#association_report'
    );

    $r->get('/ontology/association_report/:term_id')->to(
        'ontology#association_report'
    );

    $r->get('/rest/view_cart')->to('rest#view_cart');

    $r->get('/ontology')->to('ontology#search');

    $r->get('/ontology/term/:id')->to('ontology#term');

    $r->get('/markers')->to('markers#search');

    $r->get('/view/:module/:table/:id')->to('view#object');

    $self->hook(
        after_dispatch => sub {
            my $c = shift;

            if ( defined $c->param('download') ) {
                $c->res->headers->add(
                    'Content-type' => 'application/force-download' );

                my $file = $c->req->url->path;
                $file =~ s{.+/}{};

                $c->res->headers->add(
                    'Content-Disposition' => qq[attachment; filename=$file] );
            }
        }
    );

    $self->helper(make_web_link => sub {
        my $self      = shift;
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

            if ($id =~ /^\d+$/) {
                my $db      = Grm::DB->new($module);
                my $schema  = $db->schema;
                my $rs_name = camel_case($table);
                $obj = $schema->resultset($rs_name)->find($id);
            }

            my $tt = Template->new;

            $tt->process( 
                \$tt_tmpl, 
                { 
                    object => $obj,
                    %args
                }, 
                \$url 
            );

            if (my $err = $tt->error) {
                print STDERR "Error processing '$tt_tmpl': $err\n";
            }
        }
        else {
            if ( $module && $table && $id ) {
                $url = "/view/$module/$table/$id";
            }
        }

        return $url;
    });
}

1;
