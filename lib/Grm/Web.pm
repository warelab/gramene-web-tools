package Grm::Web;

use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    $self->plugin('tt_renderer');

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/')->to('root#home');

    $r->get('/search')->to('search#search');

    $r->get('/rest')->to('rest#info');

    $r->get('/rest/info')->to('rest#info');

    $r->get('/rest/search')->to('rest#search');

    $r->get('/ontology')->to('ontology#list');

    $r->get('/markers')->to('markers#search');

    $r->get('/view/:module/:table/:id')->to('view#object');
}

1;
