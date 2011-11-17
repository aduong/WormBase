#!/usr/bin/perl
# t/WormBase/API/Benchmark/corocurrent.pl

use FindBin '$Bin';
use constant ROOT => "$Bin/../../../..";

use lib ROOT.'/lib';
use lib ROOT.'/t/lib';#"$Bin/../../../lib"; # t/lib

use strict;
use warnings;
use Ace;
use IO::Handle;
use IO::Select;
use POSIX qw(WNOHANG);
use Fcntl qw(LOCK_EX);
use Time::HiRes qw(time);
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

my $WORKERS = 4;
GetOptions('workers=i' => \$WORKERS);

my $dbclass = 'WormBase::Ace';

###############################################################################
# load model information

my $dbh = Ace->connect(-host => 'dev.wormbase.org', port => 2005);

my %MODELS = do {
    open my $modelfh, '<', 'models' or die q(Couldn't open "models" file: ), $!; # hardcoded
    map { chomp; $_ => [ map { ucfirst $_ } $dbh->model($_)->tags ] } <$modelfh>;
};

undef $dbh; # children will connect on their own

###############################################################################

my $select = IO::Select->new;

my $zombies = 0;
$SIG{CHLD} = \&REAPER;

my %children;
my %poller2pid;

open my $logfh, '>', "$$.log" if DEBUG; # log file for children to share

PARENT:
while () {
    reap() if $zombies;

    # there are 2 entries in %children, per child
    # spawn more children if there are too few
    while (keys %children < $WORKERS) {
        debug("Trying to spawn child...\n") if DEBUG;
        my ($data_pipe, $poll_pipe);
        my ($child, $pid) = fork_child(\$data_pipe, \$poll_pipe);
        unless ($pid) { # child or failed fork
            die "Couldn't fork: $!" unless defined $pid;

            # close unused pipes
            close $child->{poll_reader};
            close $child->{data_writer};

            # finally run...
            child_run($data_pipe, $poll_pipe);
            exit;
        }

        # close unused pipes
        close $child->{poll_writer};
        close $child->{data_reader};

        $select->add($child->{poll_reader});

        # we need the poll_reader key because select will return it
        $children{$pid} = $child;
        $poller2pid{$child->{poll_reader}} = $pid;
    }

    for my $poller ($select->can_read) {
        defined(my $need = <$poller>) or next;
        chomp $need;
        my $pid = $poller2pid{$poller};
        my $writer = $children{$pid}->{data_writer};

        my $num_to_give = min($need, MAX_JOBS_PER_REQ);
        debug("Child with PID $pid said it needs $need more jobs. Will give $num_to_give.\n") if DEBUG;
        for (1..$num_to_give) {
            defined(my $work = <>) or last PARENT;
            print $writer $work;
        }
    }
}

while (my ($pid, $child) = each %children) {
    close $child->{data_writer} or die "Couldn't close pipe on child with PID $pid\n";
}

debug("Waiting for children to finish...\n") if DEBUG;
while (wait > 0) {} # wait for children to finish up

print "Done\n";

sub child_run {
    my ($data_pipe, $poll_pipe) = @_;

    debug("Child starting up: $$\n") if DEBUG;

    eval "require $dbclass";

    chdir ROOT.'/t';
    my ($api, $conf_hash) = WormBase::Test::API->build_api('../wormbase.conf', 'data/conf/test.conf')
        or die "Cannot get API\n";
    $api->log->info(0);
    chdir $Bin;

    my $select = IO::Select->new($data_pipe);

    my $line;
    my $reqs = 0;

    debug($$, "; connection established\n") if DEBUG;

    # in principle, the actual async calls should be located in the main loop
    # where the parent currently is forking children, since async calls are
    # essentially "creating" threads
    my $corocounter = Coro::Semaphore->new(MAX_JOBS_PER_REQ);

    while ($corocounter->down) {
        async {
          OBJECT:
            while ((my $remaining_reqs =  MAX_REQS_PER_CHILD - $reqs) > 0) {
                unless ($select->can_read(0)) {
                    debug($$, '; Telling parent to give me ', $remaining_reqs, " jobs\n");
                    print $poll_pipe $remaining_reqs, "\n"; # tell parent we need more work
                }

                last OBJECT unless defined($line = sysreadline($data_pipe));

                chomp $line;
                my ($class, $name) = split / /, $line, 2;
                unless ($class and $name) {
                    warn "Could not parse class and name from line $.\n";
                    next;
                }

                if (DEBUG) {
                    flock $logfh, LOCK_EX;
                    print {$logfh} $$, "; Fetching $class => $name\n";
                }

                my $t0 = time;
                if (my $obj = $api->fetch({aceclass => $class, name => $name})) {
                    while (my ($widget, $widgeth) = each %{$conf_hash->{sections}{species}{lc $class}{widgets}}) {
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
                    ++$reqs;
                }
                else {
                    if (DEBUG) {
                        flock $logfh, LOCK_EX;
                        print {$logfh} $$, "; $dbclass, failed to fetch $class => $name; ", $dbh->error, "\n";
                    }
                }
            }
            $corocounter->up;
        }; # end of async
    }
    debug($$, "; end of lifetime\n");
}

sub fork_child {
    my ($child_reader, $child_writer) = @_;

    my $child = {};
    pipe $child->{data_reader}, $child->{data_writer};
    pipe $child->{poll_reader}, $child->{poll_writer};

    $child->{data_writer}->autoflush(1);
    $child->{poll_writer}->autoflush(1);

    $$child_reader = $child->{data_reader};
    $$child_writer = $child->{poll_writer};

    return ($child, fork);
}

sub reap {
    $zombies = 0;
    while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
        my $poller = $children{$pid}->{poll_reader};
        $select->remove($poller);

        delete $poller2pid{$poller};
        delete $children{$pid};

        debug("Reaped child with PID $pid\n") if DEBUG;
    }
}

sub REAPER {
    ++$zombies;
}

sub sysreadline { # block and read
    my $fh = shift;

    my $str = '';
    my ($bytes_read, $buf);
    while (($bytes_read = sysread($fh, $buf, 1)) > 0) {
        $str .= $buf;
        last if $buf eq $/;
    };

    return unless $bytes_read;
    return $str;
}

sub min {
    return $_[0] < $_[1] ? $_[0] : $_[1];
}

sub debug {
    print STDERR '[', time, '] ', @_;
}

sub usage {
    die <<EOF;
Usage:
$0 [--initdbhost IHOST] [--initdbport IPORT] [--dbhost HOST] [--dbport PORT]
    [--couchdb DBNAME] [--workers NUM] --dbtype (ace|couch|socket|persistent) [listfile...]

    --initdbhost IHOST
        AceDB server host used for initialization models [localhost]
    --dbhost HOST
        AceDB server host used for queries [IHOST]
    --couchdb DBNAME
        Couch DB name [jace]
    --workers NUM
        Number of worker processes to maintain [5]
    --dbtype (ace|couch|socket|persistent)
        Whether to use Ace or Couch backend

    Will read from list files provided as arguments or from STDIN
EOF
}
