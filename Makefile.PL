use inc::Module::Install;

name           'Grm-API';
abstract       'Mojolicious version of Gramene REST/Web API';
author         'Warelab <warelab@gmail.com>';
version        '0.01';
license        'MIT';

requires       'DBI' => '1.630';
requires       'Moose' => '2.1005';
requires       'Mojolicious' => '4.53';
requires       'Mojolicious::Plugin::TtRenderer' => '1.50';
requires       'Mojolicious::Plugin::YamlConfig' => '0.1.5';
requires       'Params/Validate' => '1.08';
requires       'Sub::Identify' => '0.04';
requires       'Template' => '2.25';
requires       'Template::Plugin::Comma' => '0.04';
requires       'Variable::Magic' => '0.53';
test_requires  'Test::More'  => '0.98';

WriteAll;
