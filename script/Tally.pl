use strict;
use warnings;

my ($total_time, $count) = 0;
while (<>) {
    m/^: ([0-9.]+) ms; ([0-9.]+)/ or next;
    $total_time += $1; # in ms
    $count      += 1;
}

print $total_time / $count, " ms/obj\n";
print $count / $total_time * 1000, " obj/s\n";
