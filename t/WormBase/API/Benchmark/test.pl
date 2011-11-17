use strict;
use warnings;

use EV;
use Coro;
use Ace;

# experiment: a few large fetches and see how it goes

sub ace_connect {
    return Ace->connect(-host => 'dev.wormbase.org', -port => 2005)
        || die 'Connection error: ', Ace->error;
}

my @classes = qw(Protein Sequence Gene);

my @coros = map {
    my $class = $_;
    my $ace = ace_connect();
    async {
        print "Fetching $class\n";
        $ace->raw_query("find $class *; list");
        print "Done $class\n";
    };
} @classes;

$_->join foreach @coros;

print "\$AnyEvent::MODEL = $AnyEvent::MODEL\n";
