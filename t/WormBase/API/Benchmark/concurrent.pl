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

use constant DEBUG              => 1;
use constant MAX_JOBS_PER_REQ   => 5;
use constant MAX_REQS_PER_CHILD => 10;

BEGIN {
    die "The number of jobs per requests exceeds the maximum number of requests\n",
        "servable in a child's lifetime\n"
    if MAX_JOBS_PER_REQ > MAX_REQS_PER_CHILD;
}

my $WORKERS = 5;
GetOptions('workers=i' => \$WORKERS);

my $pm = Parallel::ForkManager->new($WORKERS);

my $logfh;
if (DEBUG) {
    open $logfh, '>', "$$.log"; # shared
    $logfh->autoflush;
}

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
    my ($api, $conf_hash) = WormBase::Test::API->build_api('../wormbase.conf', 'data/conf/test.conf')
        or die "Cannot get API\n";
    $api->log->info(0); # need this to get the fh before chdir
    chdir $Bin;

    debug($$, "; child starting\n");

    for my $req (@$reqs) {
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
    }

    debug($$, "; child dying\n");
}


sub min {
    return $_[0] < $_[1] ? $_[0] : $_[1];
}

sub debug {
    print STDERR '[', time, '] ', @_;
}
