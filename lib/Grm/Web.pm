package Grm::Web;

use File::Spec::Functions;
use Mojo::Base 'Mojolicious';

sub startup {
    my $self = shift;

    $self->plugin('tt_renderer');

    $self->plugin('yaml_config', { 
        file => $self->home->rel_file('conf/grm-web.yaml')
    });

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/')->to('root#home');
    
    $r->get('/search')->to('search#search');

    $r->any('/download/package')->to('download#package');

    $r->get('/rest')->to('rest#info');

    $r->get('/rest/info')->to('rest#info');

    $r->get('/rest/search')->to('rest#search');

    $r->get('/rest/ontology')->to('rest#ontology');

    $r->get('/ontology')->to('ontology#search');

    $r->get('/markers')->to('markers#search');

    $r->get('/view/:module/:table/:id')->to('view#object');
}

1;
