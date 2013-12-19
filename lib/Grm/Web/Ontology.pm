package Grm::Web::Ontology;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

use lib '/usr/local/gramene-lib/lib';
use Grm::DB;
use Grm::Search;
use Grm::Utils qw( camel_case commify iterative_search_values timer_calc );
use List::MoreUtils qw( uniq );

# ----------------------------------------------------------------------
sub list {
    my $self   = shift;
    my $odb    = Grm::DB->new('ontology');
    my $schema = $odb->schema;
    my @types  = sort 
        uniq( map { $_->prefix } $schema->resultset('TermType')->all );

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

# ----------------------------------------------------------------------
sub search {
    my $self = shift;

    $self->layout('default');

    $self->render;
}

1;
