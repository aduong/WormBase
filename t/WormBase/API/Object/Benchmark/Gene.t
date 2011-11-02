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
    conf_file => ['../wormbase.conf', 'data/conf/test.conf'],
});

my $widgets_hash = $t->conf->{sections}{species}{gene}{widgets};

for my $widget (sort keys %$widgets_hash) {
    subtest "Widget $widget ok" => sub {
        my $object = $t->fetch_object_ok({ name => $object_names[0] });

        my @widgets = grep defined, $widgets_hash->{$widget}{fields};
        @widgets = @{$widgets[0]} if ref $widgets[0];

        for my $field (sort @widgets) {
            $t->call_method_ok($object, $field);
        }
    };
}

done_testing;
