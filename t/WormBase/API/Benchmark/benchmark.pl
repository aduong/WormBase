#!/usr/bin/perl
# benchmark.pl

use strict;
use warnings;

use Getopt::Long;

my %VALID_ACETYPES = map { $_ => 1 } qw(Ace Ace::Couch);

my ($ACETYPE, $MIN_WORKERS, $MAX_WORKERS, $PROBABILITY, $RUNS);
GetOptions(
    'acetype=s'     => \$ACETYPE,
    'runs=i'        => \$RUNS,
    'minworkers=i'  => \$MIN_WORKERS,
    'maxworkers=i'  => \$MAX_WORKERS,
    'probability=f' => \$PROBABILITY,
);
$MIN_WORKERS //= 1;

die '--acetype must be ', join(' or ', keys %VALID_ACETYPES)
    unless $ACETYPE && $VALID_ACETYPES{$ACETYPE};

die '--probability must be positive, floating point number'
    unless $PROBABILITY && $PROBABILITY > 0;

die '--maxworkers must be positive integer'
    unless $MAX_WORKERS && $MAX_WORKERS > 0;

die '--minworkers must be a positive integer'
    unless $MIN_WORKERS > 0;

die '--runs must be positive integer'
    unless $RUNS && $RUNS > 0;

print "Remember to provide a list to either STDIN or as an argument\n";
my @list = <>; # we need the whole list

my $cmd = './concurrent.pl';
$cmd   .= ' --couch' if $ACETYPE eq 'Ace::Couch';

for my $workers ($MIN_WORKERS..$MAX_WORKERS) {
    for my $run (1..$RUNS) {
        my $logname = join('_', $ACETYPE, 'p'.$PROBABILITY,
                           'w'. $workers, 'x'.$run) . '.log';
        $logname =~ s/://g;

        print $logname, "\n";

        open my $prog, "| $cmd --workers $workers --logfile $logname";
        map { print {$prog} $_ if rand() < $PROBABILITY } @list;
    }
}
