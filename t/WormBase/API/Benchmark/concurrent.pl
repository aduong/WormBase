#!/usr/bin/perl
# t/WormBase/API/Benchmark/concurrent.pl

use FindBin '$Bin';
use constant ROOT => "$Bin/../../../..";

use lib ROOT.'/lib';
use lib ROOT.'/t/lib';#"$Bin/../../../lib"; # t/lib

use strict;
use warnings;
use Ace;
use Parallel::ForkManager;
use Time::HiRes qw(time);
use Fcntl qw(:flock);
use Getopt::Long;
use WormBase::Test::API;
use WormBase::Ace;

use constant DEBUG              => 1;
use constant MAX_REQS_PER_CHILD => 10;

my ($WORKERS, $LOGNAME, $COUCH);
GetOptions(
    'workers=i' => \$WORKERS,
    'logfile=s' => \$LOGNAME,
    'couch'     => \$COUCH,
);
$WORKERS  //= 5;
$LOGNAME  //= "$$.log";

if ($COUCH and ! WormBase::Ace->isa('Ace::Couch')) {
    die "WormBase::Ace does not extend Ace::Couch. Cannot proceed.\n";
}

my $pm = Parallel::ForkManager->new($WORKERS);

open my $logfh, '>', $LOGNAME; # shared
$logfh->autoflush;

while () {
    my @reqs;
    while (@reqs < MAX_REQS_PER_CHILD and defined($_ = <STDIN>)) {
        chomp;
        push @reqs, [split / /, $_, 2];
    }
    last unless @reqs;

    $pm->start and next;

    do_work(\@reqs);

    $pm->finish;
}

debug("Waiting for children to finish...\n");
$pm->wait_all_children;
debug("Done\n");

sub do_work {
    my $reqs = shift;

    chdir ROOT.'/t';
    my ($api, $conf_hash) = WormBase::Test::API->build_api('../wormbase.conf', 'data/conf/benchmark.conf')
        or die "Cannot get API\n";
    $api->log->info(0); # need this to get the fh before chdir
    chdir $Bin;

    debug($$, "; child starting\n");

    for my $req (@$reqs) {
        my ($class, $name) = @$req;

        if (flock $logfh, LOCK_EX) {
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

            if (flock $logfh, LOCK_EX) {
                print {$logfh} $$, "; Fetched $class => $name\n";
                print {$logfh} $$, '; time: ', $t1 - $t0, "\n";
            }
        }
        elsif (flock $logfh, LOCK_EX) {
            print {$logfh} $$, "; failed to fetch $class => $name\n";
        }
    }

    debug($$, "; child dying\n");
}

sub debug {
    print STDERR '[', time, '] ', @_ if DEBUG;
}
