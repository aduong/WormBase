#!/usr/bin/perl

use strict;
use warnings;

use Ace;
use Ace::Couch;
use Class::MOP;
use Getopt::Long;
use Parallel::ForkManager;
use Time::HiRes qw(time);;
use Fcntl qw(:flock);

use constant HOST          => 'dev.wormbase.org';
use constant PORT          => 2005;
use constant TEST_SIZE     => 20_000;
use constant WORK_PER_FORK => 100;

my ($TYPE, $WORKERS);
my $LOGFILE = "$$.log";
GetOptions(
    'type=s'    => \$TYPE,
    'workers=i' => \$WORKERS,
    'logfile=s' => \$LOGFILE,
);

die "--type invalid\n"
    unless defined $TYPE && Class::MOP::is_class_loaded($TYPE);
die "--workers must be non-negative integer\n"
    unless defined $WORKERS && $WORKERS =~ /^[0-9]+$/;

open my $logfh, '>', $LOGFILE;

my $pm = Parallel::ForkManager->new($WORKERS);

my $count = 1;
while () {
    my $start = $count;
    my $end   = ($count += WORK_PER_FORK) - 1;

    last if $count > TEST_SIZE;

    $pm->start and next;

    my $dbh = $TYPE->connect(
        -host => HOST, -port => PORT,
        -couch => {
            host => HOST, port => 5984, database => 'jace',
        },
    ) or die 'Could not connect: ', $TYPE->error;

    print 'Startup ', $$, "\n";

    my $total_time = 0;
    my ($obj, $t1, $t2);
    foreach ($start..$end) {
        $obj = sprintf('WBGene%08i', $_);
        $t1 = time;
        $obj = $dbh->fetch(
            -class => 'Gene',
            -name  => $obj,
            -fill  => 1,
        );
        $t2 = time;
        $total_time += $t2 - $t1 if $obj;
    }

    if (flock $logfh, LOCK_EX) {
        print {$logfh} $$, '; time: ', $total_time, " s\n";
    }

    print 'Shutdown ', $$, "\n";

    $pm->finish;
}

$pm->wait_all_children;
