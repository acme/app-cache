#!perl
use strict;
use lib qw(lib t/lib);
use Test::More tests => 40;
use File::Spec::Functions qw(rel2abs);
use_ok('App::Cache');
use_ok('App::Cache::Test');

my $cache = App::Cache::Test->new();
$cache->code;
$cache->file;
$cache->scratch;
$cache->url( 'file:/' . rel2abs( $INC{'App/Cache/Test.pm'} ) );
$cache->url('http://www.astray.com/');
$cache->cleanup;

