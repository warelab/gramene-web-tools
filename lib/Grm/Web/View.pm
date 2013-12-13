package Grm::Web::View;

use Mojo::Base 'Mojolicious::Controller';
use Grm::DB;
use Grm::Utils qw( camel_case );

# ----------------------------------------------------------------------
sub object {
    my $self    = shift;
    my $module  = $self->param('module');
    my $table   = $self->param('table');
    my $id      = $self->param('id');
    my $db      = Grm::DB->new( $module );
    my $schema  = $db->schema;
    my $rs_name = camel_case( $table );
    my $obj     = $schema->resultset( $rs_name )->find( $id );

    $self->layout('default');

    $self->respond_to(
        json => sub {
            $self->render( json => { 
                module => $self->param('module'),
                table  => $self->param('table'),
                id     => $self->param('id'),
            });
        },

        html => sub {
            my %args = (
                module => $module,
                table  => $table,
                id     => $id,
                obj    => $obj,
                db     => $db,
                schema => $schema,
            );

            my $conf  = $self->config;
            my %views = %{ $conf->{'view'}{'template'} || {} };
            my $test  = join '-', $module, $table;

            for my $key ( %views ) {
                if ( $test eq $key || $test =~ /$key/ ) {
                    $args{'template'} = $views{ $key };
                    last;
                }
            }

            $self->render( %args );
        },
    );
}

1;
