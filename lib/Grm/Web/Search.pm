package Grm::Web::Search;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-lib/lib';
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

# This action will render a template
sub search {
    my $self   = shift;
    my $search = Grm::Search->new;
#    my $timer  = timer_calc();
    my $req    = $self->req;
    my $res    = {};

    $self->layout('default');

    $self->render();

#    $self->respond_to(
#        json => sub {
#            $self->render( json => $res );
#        },
#        html => sub { 
#            $self->render( 
#                results => $res,
#                config  => $self->config,
#            );
#        },
#        txt => sub { 
#            $self->render( text => Dumper($res) );
#        },
#    );
}

1;
