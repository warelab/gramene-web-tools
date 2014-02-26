use inc::Module::Install;

name           'Grm-Web';
abstract       'Mojolicious version of Gramene REST/Web API';
author         'Ken Youens-Clark <kclark@cshl.edu>';
version        '0.01';
license        'MIT';

requires 'DBI'                             => '1.630';
requires 'DBIx::Class'                     => '0.08260';
requires 'Moose'                           => '2.1005';
requires 'Mojolicious'                     => '4.84';
requires 'Mojolicious::Plugin::TtRenderer' => '1.50';
requires 'Mojolicious::Plugin::YamlConfig' => '0.1.5';
requires 'MongoDB::Database'               => '0.702.2';
requires 'Params/Validate'                 => '1.08';
requires 'Sub::Identify'                   => '0.04';
requires 'Template'                        => '2.25';
requires 'Template::Plugin::Comma'         => '0.04';
requires 'Template::Plugin::JSON'          => '0.06';
requires 'Template::Plugin::POSIX'         => '0.05';
requires 'Template::Plugin::Page'          => '0.10';
requires 'Variable::Magic'                 => '0.53';

test_requires 'Test::More'                 => '0.98';

WriteAll;
