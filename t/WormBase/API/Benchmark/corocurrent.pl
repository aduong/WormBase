#!/usr/bin/perl
# t/WormBase/API/Benchmark/corocurrent.pl

use strict;
use warnings;

use FindBin '$Bin';
use constant ROOT => "$Bin/../../../..";

use lib ROOT.'/lib';
use lib ROOT.'/t/lib';#"$Bin/../../../lib"; # t/lib

use Event;
use Coro;
use Ace::SocketServer;

use Ace;
use POSIX qw(WNOHANG);
use Fcntl qw(LOCK_EX);
use Time::HiRes qw(time);
use Parallel::ForkManager;
use WormBase::Test::API;

use constant DEBUG              => 1;

use constant NUM_FORKS          => 10;
use constant MAX_COROS          => 5;
use constant MAX_JOBS_PER_FORK  => 20;

use constant MODEL_FILE         => 'models';
use constant MODEL_HOST         => 'dev.wormbase.org';
use constant MODEL_PORT         => 2005;

debug('\$AnyEvent::MODEL = ', AnyEvent::detect, "\n");
debug('Ace::SocketServer location: ', $INC{'Ace/SocketServer.pm'}, "\n");

# our $debug_serv;
# if (DEBUG) {
#     require Coro::Debug;
#     $debug_serv = Coro::Debug->new_unix_server('debug.sock');
# }

my $pm = Parallel::ForkManager->new(NUM_FORKS);

open my $logfh, '>', "$$.log" if DEBUG; # log file for children to share

while () {
    my @reqs;
    while (@reqs < MAX_JOBS_PER_FORK and defined($_ = <STDIN>)) {
        chomp;
        push @reqs, [split / /, $_, 2];
    }
    last unless @reqs;

    $pm->start and next;

    debug("Child starting up: $$\n") if DEBUG;

    my $lock = Coro::Semaphore->new(MAX_COROS);
    my @coros = map { async(\&do_work, $lock, $_) } @reqs;

    foreach (async{ Event::loop }, @coros) {
        $_->join;
        $lock->wait;
    }

    debug("Child dying: $$\n");

    $pm->finish;
}

debug("Waiting for children to finish...\n");
$pm->wait_all_children;
debug("Done\n");

sub do_work {
    my $guard = shift->guard;
    my $req  = shift;

    chdir ROOT.'/t';
    my ($api, $conf_hash) = WormBase::Test::API->build_api('../wormbase.conf', 'data/conf/test.conf')
        or die "Cannot get API\n";
    $api->log->info(0); # need this to get the fh before chdir
    chdir $Bin;

    debug($$, "; started Coro\n");

    my ($class, $name) = @$req;

    if (DEBUG) {
        flock $logfh, LOCK_EX;
        print {$logfh} $$, "; Fetching $class => $name\n";
    }

    my $t0 = time;
    if (my $obj = $api->fetch({aceclass => $class, name => $name})) {
        while (my ($widget, $widgeth)
               = each %{$conf_hash->{sections}{species}{lc $class}{widgets}}) {
            my @fields = grep defined, $widgeth->{fields};
            @fields = @{$fields[0]} if ref $fields[0];
            for my $field (@fields) {
                my $data = eval { $obj->$field };
            }
        }
        my $t1 = time;

        if (DEBUG) {
            flock $logfh, LOCK_EX;
            print {$logfh} $$, "; Fetched $class => $name\n";
            print {$logfh} $$, '; time: ', $t1 - $t0, "\n";
        }
    }
    elsif (DEBUG) {
        flock $logfh, LOCK_EX;
        print {$logfh} $$, "; failed to fetch $class => $name\n";
    }


    debug($$, "; dying Coro\n");
}

sub min {
    return $_[0] < $_[1] ? $_[0] : $_[1];
}

sub debug {
    print STDERR '[', time, '] ', @_ if DEBUG;
}
