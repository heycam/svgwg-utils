#!/usr/bin/perl -w

use strict;

# minutes-collector.pl
#
# Reads the RRSAgent-generated minutes URL specified on the command line
# and updates the [[Topic database]] page on the SVG WG wiki to add
# its contents.
#
# Configuration
# =============
#
# Create a file named ~/.svgwg-utils/account that has your W3C account
# username on the first line and the password on the second line.  This
# account will be used to log in to and edit the wiki.

sub usage {
  die "usage: $0 URL YYYY-MM-DD\n       $0 --scan-input\n";
}

my $url;
my $date;

if (@ARGV == 1) {
  usage() unless $ARGV[0] eq '--scan-input';

  while (<STDIN>) {
    if (m{http://www\.w3\.org/(\d\d\d\d)/(\d\d)/(\d\d)-svg-minutes\.html}) {
      $url = $&;
      $date = "$1-$2-$3";
      last;
    }
  }

  exit 0 unless defined $url;
} elsif (@ARGV == 2) {
  $url = $ARGV[0];
  $date = $ARGV[1];
} else {
  usage();
}

die "date has wrong format\n" unless $date =~ /^\d\d\d\d-\d\d-\d\d$/;

my $HOME = $ENV{HOME};
die "\$HOME is not set" unless defined $HOME;
die "\$HOME is not a directory" unless -d $HOME;

my $dir = "$HOME/.svgwg-utils";
unless (-d $dir) {
  mkdir $dir or die "couldn't create $dir";
}

die "could not read $dir/account" unless -f "$dir/account";

open FH, "$dir/account" or die "could not read ~/.svgwg-utils/account";
my $username = <FH>;
my $password = <FH>;
chomp $username;
chomp $password;
close FH;

die "error parsing ~/.svgwg-utils/account" unless defined($username) && defined($password);

sub read_fh {
  my $fh = shift;
  local $/;
  my $contents = <$fh>;
  close $fh;
  return $contents;
}

sub read_cmd {
  my $fh;
  open $fh, '-|', @_;
  return read_fh($fh);
}

sub read_file {
  my $fn = shift;
  my $fh;
  open $fh, '<', $fn;
  return read_fh($fh);
}

# Step 1: Get the contents of the [[Topic database]] page.

my $db = read_cmd('curl', '-s', 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topic_database&action=raw');

# Step 2: Check if we already have these minutes in the database.

exit 0 if $db =~ /^== Meetings ==.*^\* $date/ms;

# Step 3: Read the minutes URL and parse out the topics and resolutions.

my $minutesPage = read_cmd('curl', '-s', $url);

# Make it easier to split out sections between <h3>s.
$minutesPage .= '<h3';

my $wikitext = "* $date: $url\n";

while ($minutesPage =~ s/^.*?<h3 id="item0*(\d+)">(.*?)<\/h3>(.*?)<h3/<h3/s) {
  my $index = int($1);
  my $topic = $2;
  my $contents = $3;
  $topic =~ s/^\s+//;
  $topic =~ s/\s+$//;
  $topic =~ s/\s\s+/ /g;
  $wikitext .= "** $index. $topic\n";

  $contents =~ s/\s\s+/ /g;

  while ($contents =~ s/<strong class=['"]resolution['"]>(RESOLUTION:.*?)<\/strong>//s) {
    my $res = $1;
    $res =~ s/^\s+//;
    $res =~ s/\s+$//;
    $res =~ s/\s\s+/ /g;
    $wikitext .= "*** $res\n";
  }

  while ($contents =~ s/Created ACTION-(\d+) - (.*?) \[on (.*?) -//) {
    my $id = $1;
    my $desc = $2;
    my $who = $3;
    $desc =~ s/^\s+//;
    $desc =~ s/\s+$//;
    $desc =~ s/\s\s+/ /g;
    $wikitext .= "*** [http://www.w3.org/Graphics/SVG/WG/track/actions/$id ACTION-$id] - $desc (on $who)\n";
  }

  while ($contents =~ s/Created ISSUE-(\d+) - (.*?) Please complete additional details//) {
    my $id = $1;
    my $desc = $2;
    $desc =~ s/^\s+//;
    $desc =~ s/\s+$//;
    $desc =~ s/\s\s+/ /g;
    $wikitext .= "*** [http://www.w3.org/Graphics/SVG/WG/track/issues/$id ISSUE-$id] - $desc\n";
  }
}

$db =~ /(.*^== Meetings ==)\n+(.*)/ms;
my $newdb = "$1\n\n$wikitext$2";

open FH, ">$dir/page";
print FH $newdb;
close FH;

# Step 4: Get the login page.

system ">$dir/cookies";

my $loginPage = read_cmd('curl', '-s',
                         '-c', "$dir/cookies",
                         'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=Main+Page');
die 'could not extract wpLoginToken from login page' unless $loginPage =~ /name="wpLoginToken" value="([0-9a-f]+)"/;
my $wpLoginToken = $1;

# Step 5: Log in to the wiki.

my $action = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&action=submitlogin&type=login&returnto=Main+Page';
my $wpName = $username;
my $wpPassword = $password;
my $wpDomain = 'W3C+Accounts';
my $wpRemember = '1';
my $wpLoginattempt = 'Log+in';

system('curl', '-s', '-b', "$dir/cookies", '-c', "$dir/cookies", '-H',
       'Referer: https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=&returntoquery=&fromhttp=1',
       '--data', "wpName=$wpName&wpPassword=$wpPassword&wpDomain=$wpDomain&wpRemember=$wpRemember&wpLoginattempt=$wpLoginattempt&wpLoginToken=$wpLoginToken",
       "$action");
die 'submitting login form did not result in us being logged in' unless (system("grep -q wikidb_svg_UserID $dir/cookies") >> 8 == 0);

# Step 6: Get the edit page.

my $editPage = read_cmd('curl', '-s',
                        '-b', "$dir/cookies",
                        '-c', "$dir/cookies",
                        'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topic_database&action=edit');
die 'could not extract wpEditToken from edit page' unless $editPage =~ /value="([^"]+)" name="wpEditToken"/;
my $wpEditToken = $1;
die 'could not extract wpAutoSummary from edit page' unless $editPage =~ /value="([^"]+)" name="wpAutoSummary"/;
my $wpAutoSummary = $1;
die 'could not extract wpStarttime from edit page' unless $editPage =~ /value="(\d*)" name="wpStarttime"/;
my $wpStarttime = $1;
die 'could not extract wpEdittime from edit page' unless $editPage =~ /value="(\d*)" name="wpEdittime"/;
my $wpEdittime = $1;
die 'could not extract oldid from edit page' unless $editPage =~ /value="([^"]*)" name="oldid"/;
my $oldid = $1;

# Step 7: Post the new page content.

$action = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topic_database&action=submit';

my $referer = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topic_database&action=edit';
my $wpSection = '';
my $wpScrolltop = '0';
my $format = 'text/x-wiki';
my $model = 'wikitext';
my $wpSummary = "Added minutes for $date (by minutes-collector.pl)";
my $wpSave = 'Save page';

system('curl', '-s',
       '-b', "$dir/cookies",
       '-c', "$dir/cookies",
       '-H', "Referer: $referer",
       '-F', 'wpAntispam=',
       '-F', "wpSection=$wpSection",
       '-F', "wpStarttime=$wpStarttime",
       '-F', "wpEdittime=$wpEdittime",
       '-F', "wpScrolltop=$wpScrolltop",
       '-F', "wpAutoSummary=$wpAutoSummary",
       '-F', "oldid=$oldid",
       '-F', "format=$format",
       '-F', "model=$model",
       '-F', "wpTextbox1=<$dir/page",
       '-F', "wpSummary=$wpSummary",
       '-F', "wpSave=$wpSave",
       '-F', "wpEditToken=$wpEditToken",
       $action);
die "updating page failed" unless ($? >> 8 == 0);

unlink "$dir/page";
