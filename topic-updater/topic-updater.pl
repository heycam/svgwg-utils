#!/usr/bin/perl -w

use strict;

if (@ARGV == 0) {
  print <<EOF;
usage: $0 ACCOUNT

ACCOUNT
  Name of a file containing the username and the password, on two lines,
  of the http://www.w3.org/Graphics/SVG/WG/wiki/ account to use.
EOF
  exit 1;
}

my $accountfn = $ARGV[0];
open FH, $accountfn;
my $username = <FH>;
my $password = <FH>;
chomp $username;
chomp $password;
close FH;

die unless defined($username) && defined($password);

my %topics = ();
my %telcons = ();
my %meetings = ();
my %links = ();

# Step -1: Get the contents of the [[Topic database]] page.

my $mode = 'looking-for-topics';
my $topic;
my $meeting;

open DB, "curl -s 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topic_database&action=raw' |";
while (<DB>) {
  chomp;
  if ($mode eq 'looking-for-topics') {
    if ($_ eq '== Topics ==') {
      $mode = 'topics';
      next;
    }
  } elsif ($mode eq 'topics') {
    if (/^=== (.*) ===$/) {
      $topic = $1;
      $topics{$topic} = { description => '', links => [] };
    } elsif (/^\* (.*)/) {
      my $link = $1;
      push(@{$topics{$topic}{links}}, $link);
    } elsif ($_ eq '== Teleconferences ==') {
      $mode = 'telcons';
      next;
    } elsif (/^==/) {
      die "unexpected input line '$_'";
    } else {
      if (defined $topic) {
        $topics{$topic}{description} .= "$_\n";
      }
    }
  } elsif ($mode eq 'telcons') {
    if (/^\* \[([^ ]+) Minutes ([0-9-]+)\]/) {
      my $link = $1;
      my $date = $2;
      $telcons{$date} = $link;
      if ($link =~ /^(.*)#(.*)/) {
        $links{$1} = "Minutes $date";
      } else {
        $links{$link} = "Minutes $date";
      }
    } elsif (/^\s*$/) {
    } elsif ($_ eq '== Meetings ==') {
      $mode = 'meetings';
    } else {
      die "unexpected input line '$_'";
    }
  } elsif ($mode eq 'meetings') {
    if (/^=== \[\[F2F\/([^]]+)\]\] ===$/) {
      $meeting = $1;
      $meetings{$meeting} = { name => $meeting, days => { } };
    } elsif (/^\s*$/) {
    } elsif (/^\* \[([^ ]+) Minutes ([0-9-]+) \(day (\d+)\)\]$/) {
      my $link = $1;
      my $date = $2;
      my $day = $3;
      $meetings{$meeting}{days}{$day} = $1;
      if ($link =~ /^(.*)#(.*)/) {
        $links{$1} = "$meeting minutes, day $day ($date)";
      } else {
        $links{$link} = "$meeting minutes, day $day ($date)";
      }
    } else {
      die "unexpected input line '$_'";
    }
  }
}
close DB;

open FH, '>page.txt';
print FH <<EOF;
''Note that this page is automatically generated from [[Topic database]].  Any manual changes to this page are likely to be lost!''

EOF

for (sort keys %topics) {
  print FH "== $_ ==\n\n";
  my $desc = $topics{$_}{description};
  $desc =~ s/^\n+//;
  $desc =~ s/\n+$//;
  print FH "$desc\n\n";
  for my $link (@{$topics{$_}{links}}) {
    my $linkName;
    if ($link =~ /^(.*)#(.*)/) {
      if (defined $links{$1}) {
        $linkName = $links{$1};
      }
    } else {
      if (defined $links{$link}) {
        $linkName = $links{$link};
      }
    }
    if (defined $linkName) {
      print FH "* [$link $linkName]\n";
    } else {
      print FH "* $link\n";
    }
  }
}

close FH;

system('cmp -s page.txt lastpage.txt');
exit 0 if ($? >> 8) == 0;

# Step 0: Get the login page.

system '>cookies.txt';

my $loginPage = `curl -s -c cookies.txt https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=Main+Page`;
die unless $loginPage =~ /name="wpLoginToken" value="([0-9a-f]+)"/;

my $wpLoginToken = $1;

# Step 1: Log in to the wiki.

my $action = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&action=submitlogin&type=login&returnto=Main+Page';
my $wpName = $username;
my $wpPassword = $password;
my $wpDomain = 'W3C+Accounts';
my $wpRemember = '1';
my $wpLoginattempt = 'Log+in';

system("curl -s -b cookies.txt -c cookies.txt -H 'Referer: https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=&returntoquery=&fromhttp=1' --data 'wpName=$wpName\&wpPassword=$wpPassword\&wpDomain=$wpDomain\&wpRemember=$wpRemember\&wpLoginattempt=$wpLoginattempt&wpLoginToken=$wpLoginToken' '$action'");
die "login failed" unless (system('grep -q wikidb_svg_UserID cookies.txt') >> 8 == 0);

# Step 2: Get the edit page.

my $editPage = `curl -s -b cookies.txt -c cookies.txt 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topics&action=edit'`;
die unless $editPage =~ /value="([^"]+)" name="wpEditToken"/;
my $wpEditToken = $1;
die unless $editPage =~ /value="([^"]+)" name="wpAutoSummary"/;
my $wpAutoSummary = $1;
die unless $editPage =~ /value="(\d*)" name="wpStarttime"/;
my $wpStarttime = $1;
die unless $editPage =~ /value="(\d*)" name="wpEdittime"/;
my $wpEdittime = $1;
die unless $editPage =~ /value="([^"]*)" name="oldid"/;
my $oldid = $1;

# Step 3: Post the new page content.

$action = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topics&action=submit';

my $referer = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topics&action=edit';
my $wpSection = '';
my $wpScrolltop = '0';
my $format = 'text/x-wiki';
my $model = 'wikitext';
my $wpTextbox1 = 'The content of the page.';
my $wpSummary = 'Automatically generated from [[Topic database]]';
my $wpSave = 'Save page';

system("curl -s -b cookies.txt -c cookies.txt -H 'Referer: $referer' -F 'wpAntispam=' -F 'wpSection=$wpSection' -F 'wpStarttime=$wpStarttime' -F 'wpEdittime=$wpEdittime' -F 'wpScrolltop=$wpScrolltop' -F 'wpAutoSummary=$wpAutoSummary' -F 'oldid=$oldid' -F 'format=$format' -F 'model=$model' -F 'wpTextbox1=<page.txt' -F 'wpSummary=$wpSummary' -F 'wpSave=$wpSave' -F 'wpEditToken=$wpEditToken' '$action'");
die "Updating page failed" unless ($? >> 8 == 0);

system('cp page.txt lastpage.txt');
