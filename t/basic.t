use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('Grm::Web');
$t->get_ok('/')->status_is(302)->content_like(qr/Search for something/i);

done_testing();
