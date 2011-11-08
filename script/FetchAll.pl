# scripts/fetchall.pl
# sequentially queries a server for objects' widgets and writes them to disk

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use Config::General;
use FindBin '$Bin';
BEGIN { chdir "$Bin/.." }
use lib 'lib';
use File::Path qw(make_path);
use File::Slurp qw(write_file);
use File::Spec::Functions qw(catdir catfile);
use File::Temp;
use Time::HiRes qw(time);
use Parallel::ForkManager;

my $ua = LWP::UserAgent->new(
    timeout    => 60,
    cookie_jar => HTTP::Cookies->new(file => File::Temp->new->filename),
);

my $file = shift @ARGV or die "Need list of objects.\n";
my $host= shift @ARGV or die "Need host.\n";;
my $configfile = 'wormbase.conf';
my $numconns = shift(@ARGV) // 5;

my $response = $ua->get("http://$host/");
die "Couldn't get root document!: ", $response->status_line, "\n" unless $response->is_success;
$ua->cookie_jar->scan(sub {
                          local $\ = "\n";
                          print foreach grep defined, @_;
});

open my $handle, '<', $file;

# read in the config file to allow spec/resource determination

my %config;
if ($configfile) {
    my $conf = Config::General->new($configfile);
    %config = $conf->getall;
}

my $pm = Parallel::ForkManager->new($numconns);

my $total_time = 0;

my $count = 0;
my $content;
my $section;
my $continue = 1;

my $ppid = $$;
make_path($ppid);
MAIN:
while (my $model_name = <$handle>) {
    chomp $model_name;
    $model_name = lc $model_name;
    print "$model_name\n";

    $section = exists $config{sections}{species}{$model_name}
             ? 'species' : 'resources';

    my @widgets = map { lc $_ } keys %{$config{sections}{$section}{$model_name}{widgets}};

  OBJECT:
    while (my $line = <$handle>) {
        chomp $line;
        last if $line eq '//---';

        print $line, "\n";
        $pm->start and next;
        open STDOUT, '>', "$ppid/$$.log";

        foreach my $widget (@widgets) {
            next if $widget eq 'reference';
            my $url = "http://$host/rest/widget/$model_name/$line/$widget";

            print "$url\n";
            my $t0 = time;
            my $response = $ua->get($url);
            my $t1 = time;
            if ($response->is_success) {
                ++$count;
                my $delta = $t1 - $t0;
                $total_time += $delta;
                print ': ', $delta*1000, ' ms; ', 1/$delta, "/s\n";
            }
            else {
                print "----> FAIL\n";
            }
        }

        $pm->finish;
    }
}
