package Grm::Web::Markers;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-40/gramene-lib/lib';
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );

# ----------------------------------------------------------------------
sub search {
    my $self = shift;

    my @markers = qw( RM1 RM2 RM3 );

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { markers => \@markers } );
        },
        html => sub { 
            $self->render( markers => \@markers );
        },
        txt => sub { 
            $self->render( text => Dumper({ markers => \@markers }));
        },
    );
}

1;
