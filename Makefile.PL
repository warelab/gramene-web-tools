use inc::Module::Install;

# Define metadata
name           'Grm-API';
abstract       'Mojolicious version of Gramene REST/Web API';
author         'Warelab <warelab@gmail.com>';
version        '0.01';
license        'MIT';


# Specific dependencies
requires       'Mojolicious' => '4.53';
requires       'Mojolicious::Plugin::TtRenderer' => '1.50';
test_requires  'Test::More'  => '0.98';

WriteAll;
