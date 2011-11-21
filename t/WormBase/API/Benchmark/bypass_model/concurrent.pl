#!/usr/bin/perl

use strict;
use warnings;

use Ace;
use Ace::Couch;
use Class::MOP;
use Getopt::Long;
use Parallel::ForkManager;

use constant HOST          => 'dev.wormbase.org';
use constant PORT          => 2005;
use constant TEST_SIZE     => 20_000;
use constant WORK_PER_FORK => 100;

my ($TYPE, $WORKERS);
GetOptions(
    'type=s'    => \$TYPE,
    'workers=i' => \$WORKERS,
);

die "--type invalid\n"
    unless defined $TYPE && Class::MOP::is_class_loaded($TYPE);
die "--workers must be non-negative integer\n"
    unless defined $WORKERS && $WORKERS =~ /^[0-9]+$/;

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

    my $obj;
    foreach ($start..$end) {
        $obj = sprintf('WBGene%08i', $_);
        $dbh->fetch(
            -class => 'Gene',
            -name  => $obj,
            -fill  => 1,
        ) and print $obj, "\n";
    }

    $pm->finish;
}

$pm->wait_all_children;
