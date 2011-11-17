#!/usr/bin/perl

use strict;
use warnings;
use List::Util 'sum';

my @times;

while (<>) {
    next unless /\d+; time: ([0-9.]+)/;
    push @times, $1;
}

@times = sort { $a <=> $b } @times;
my $total_time = sum @times;
my $count = @times;


print 'Total time: ', $total_time, " s\n";
print 'Count: ', $count, "\n";
print 'Average: ', $total_time/$count, ' s, ', $count/$total_time, "/s\n";
print 'Median: ', (@times % 2 ? $times[$#times/2] : ($times[$#times/2] + $times[$#times/2+1])/2), " s\n";
