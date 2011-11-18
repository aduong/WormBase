use strict;
use warnings;

use List::Util 'shuffle';
use Time::HiRes 'time';

use EV;
use Coro::Debug;
use Coro;
use Ace::SocketServer; # load this in so we can detect it
use Ace;

use constant DEBUG => 1;

# experiment: a few large fetches and see how it goes

print "\$AnyEvent::MODEL = ", AnyEvent::detect, "\n";
print "Coro::Handle from: ", $INC{'Coro/Handle.pm'}, "\n";
print "Coro::Socket from: ", $INC{'Coro/Socket.pm'}, "\n";
print "SocketServer from: ", $INC{'Ace/SocketServer.pm'}, "\n";

open my $fh, '<', 'models' or die 'Could not open models file: ', $!;
my @classes = map { chomp; $_ } <$fh>;

our $server = Coro::Debug->new_unix_server('debug.sock') if DEBUG;

my @coros = map {
    my $class = $_;
    async {
        my $ace = ace_connect();
        print "Fetching $class\n";
        $ace->raw_query("find $class");
        $ace->raw_query('list');
        print "Done $class\n";
    };
} @classes;

foreach (@coros) {
    $_->join;
}

sub ace_connect {
    return Ace->connect(-host => 'dev.wormbase.org', -port => 2005)
        || die 'Connection error: ', Ace->error;
}
