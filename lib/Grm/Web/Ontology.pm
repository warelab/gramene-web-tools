package Grm::Web::Ontology;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-lib/lib';
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

# ----------------------------------------------------------------------
sub list {
    my $self = shift;

    my @types = qw( go po to gro eo gr_tax );

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { types => \@types } );
        },
        html => sub { 
            $self->render( types => \@types );
        },
        txt => sub { 
            $self->render( text => Dumper({ types => \@types }) );
        },
    );
}

1;
