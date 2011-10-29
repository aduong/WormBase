# t/WormBase/API/Object/Benchmark/Gene.t

use strict;
use warnings;

BEGIN {
      use FindBin '$Bin';
      chdir "$Bin/../../../.."; # /t
      use lib 'lib';
      use lib '../lib';
}

use Test::More;
use WormBase::Test::API::Object;

my @object_names = qw(WBGene00000018); # highly linked objects

my $t = WormBase::Test::API::Object->new({
    class => 'Gene',
    conf_file => 'data/conf/test.conf',
});

# don't want to run compliance checks in this test

my @objects = map { $t->fetch_object_ok({ name => $_ }) } @object_names;
my @methods = sort grep { !/^_/ }
              map { $_->name } $t->get_class_specific_methods;

$t->call_method_ok($t->fetch_object_ok({ name => $object_names[0] }), $_)
    foreach @methods;

done_testing;
