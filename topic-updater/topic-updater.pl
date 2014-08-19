#!/usr/bin/perl -w

# topic-updater.pl
#
# Reads the [[Topic database]] page on the SVG WG wiki and updates the
# [[Topics]] page based on it.
#
# Configuration
# =============
#
# Create a file named ~/.topic-updater/account that has your W3C account
# username on the first line and the password on the second line.  This
# account will be used to log in to and edit the wiki.
#
# Format of [[Topic database]]
# ============================
#
# The source wiki text of the [[Topic database]] page must be formatted
# as follows.  There are three top-level sections that must be present:
# the "Topics" section, the "Teleconferences" section and the "Meetings"
# section.  The sections must occur in this order.
#
# The == Topics == section
# ------------------------
#
# This section lists the topics that links to meeting minute discussions
# will be sorted under.  Each topic is a sub-section that consists of
# a short description of the topic followed by a bulleted list item for
# each link to a teleconference of F2F meeting minutes page where that
# topic was discussed.
#
# Example:
#
#   == Topics ==
#
#   === Replacing xlink:href ===
#
#   Discussions about replacing xlink:href with href or src attributes.
#
#   * http://www.w3.org/2013/01/02-svg-minutes.html#item02
#   * http://www.w3.org/2014/03/04-svg-minutes.html#item01
#
# The == Teleconferences == section
# ---------------------------------
#
# This section lists links to minutes from teleconferences.  Each link
# must be a bulleted list item with the link text set to "Minutes YYYY-DD-MM",
# where YYYY-MM-DD is the date the teleconference was held.
#
# Example:
#
#   == Teleconferences ==
#
#   * [http://www.w3.org/2014/08/14-svg-minutes.html Minutes 2014-08-14]
#   * [http://www.w3.org/2014/08/07-svg-minutes.html Minutes 2014-08-07]
#
# The == Meetings == section
# --------------------------
#
# This section lists links to minutes for F2F meetings.  Each F2F is
# a sub-section whose title is a link to the wiki page for the F2F.
# Each link must be a bulleted list item with the link text set to
# "Minutes YYYY-MM-DD (day n)" where YYYY-MM-DD is the dates of the
# day's meeting and n is the day number of the meeting.
#
# Example:
#
#   == Meetings ==
#
#   === [[F2F/Leipzig 2014]] ===
#
#   * [http://www.w3.org/2014/04/07-svg-minutes.html Minutes 2014-04-07 (day 1)]
#   * [http://www.w3.org/2014/04/08-svg-minutes.html Minutes 2014-04-08 (day 2)]
#   * [http://www.w3.org/2014/04/09-svg-minutes.html Minutes 2014-04-09 (day 3)]

use strict;

my $HOME = $ENV{HOME};
die "\$HOME is not set" unless defined $HOME;
die "\$HOME is not a directory" unless -d $HOME;

my $dir = "$HOME/.topic-updater";
unless (-d $dir) {
  mkdir $dir or die "couldn't create $dir";
}

die "could not read $dir/account" unless -f "$dir/account";

open FH, "$dir/account" or die "could not read ~/.topic-updater/account";
my $username = <FH>;
my $password = <FH>;
chomp $username;
chomp $password;
close FH;

die "error parsing ~/.topic-updater/account" unless defined($username) && defined($password);

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
      die "unexpected input line '$_' in mode $mode";
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
      die "unexpected input line '$_' in mode $mode";
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
      die "unexpected input line '$_' in mode $mode";
    }
  }
}
close DB;

open FH, ">$dir/page" or die "could not write to $dir/page";
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

system('cmp -s page lastpage');
exit 0 if ($? >> 8) == 0;

# Step 0: Get the login page.

system ">$dir/cookies";

sub read_cmd {
  my $fh;
  local $/;
  open $fh, '-|', @_;
  my $contents = <$fh>;
  close $fh;
  return $contents;
}

my $loginPage = read_cmd('curl', '-s',
                         '-c', "$dir/cookies",
                         'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=Main+Page');
die 'could not extract wpLoginToken from login page' unless $loginPage =~ /name="wpLoginToken" value="([0-9a-f]+)"/;
my $wpLoginToken = $1;

# Step 1: Log in to the wiki.

my $action = 'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&action=submitlogin&type=login&returnto=Main+Page';
my $wpName = $username;
my $wpPassword = $password;
my $wpDomain = 'W3C+Accounts';
my $wpRemember = '1';
my $wpLoginattempt = 'Log+in';

system('curl', '-s', '-b', "$dir/cookies", '-c', "$dir/cookies", '-H',
       'Referer: https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Special:UserLogin&returnto=&returntoquery=&fromhttp=1',
       '--data', 'wpName=$wpName&wpPassword=$wpPassword&wpDomain=$wpDomain&wpRemember=$wpRemember&wpLoginattempt=$wpLoginattempt&wpLoginToken=$wpLoginToken',
       "$action");
die 'submitting login form did not result in us being logged in' unless (system("grep -q wikidb_svg_UserID $dir/cookies") >> 8 == 0);

# Step 2: Get the edit page.

my $editPage = read_cmd('curl', '-s',
                        '-b', "$dir/cookies",
                        '-c', "$dir/cookies",
                        'https://www.w3.org/Graphics/SVG/WG/wiki/index.php?title=Topics&action=edit');
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

system('mv', "$dir/page", "$dir/lastpage");
