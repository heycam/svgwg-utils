#!/usr/bin/perl -w

# topic-updater.pl
#
# Reads the [[Topic database]] page on the SVG WG wiki and updates the
# [[Topics]] page based on it.
#
# Configuration
# =============
#
# Create a file named ~/.svgwg-utils/account that has your W3C account
# username on the first line and the password on the second line.  This
# account will be used to log in to and edit the wiki.
#
# Format of [[Topic database]]
# ============================
#
# The source wiki text of the [[Topic database]] page must be formatted
# as follows.  There are two top-level sections that must be present:
# the "Topics" section and the "Meetings" section.  The sections must occur in
# this order.
#
# The == Topics == section
# ------------------------
#
# This section lists the topics that links to meeting minute discussions
# will be sorted under.  Each topic is a sub-section that consists of
# a short description of the topic.  It is not necessary to have a
# topic defined in this section; an entry in the Meetings section below
# can name a topic without it being defined here -- it will just have
# no description on [[Topics]].
#
# Example:
#
#   == Topics ==
#
#   === Replacing xlink:href ===
#
#   Discussions about replacing xlink:href with href or src attributes.
#
# The == Meetings == section
# --------------------------
#
# This section lists links to minutes from teleconferences and F2F meetings.
# The contents of this section is a bulleted list of up to three levels:
#
#   * The top level lists the meeting date, an optional name, and a link to
#     the minutes as published by RRSAgent.  The format of the bullet must
#     be "* YYYY-MM-DD: http://www.w3.org/YYYY/MM/DD-svg-minutes.html" with
#     the optional name appearing just before the colon.
#
#   * The second level lists the topics that appear in the minutes.  The
#     format of this line is "** n. Topic name" where "n" is the agenda order
#     number as it appears in the minutes.  The number can be left off if
#     the minutes being linked to aren't RRSAgent-generated.
#
#   * The third level lists resolutions that were made during the discussion
#     of the topic.  The format of this line is "*** RESOLUTION: Text of the
#     resolution".
#
# Example:
#
#   == Meetings ==
#
#   * 2014-08-14: http://www.w3.org/2014/08/14-svg-minutes.html
#   ** 1. Charter
#   ** 2. paint-order
#   ** 3. F2F planning
#   *** RESOLUTION: We will meet at Cam's house.
#   * 2014-04-09 [[F2F/Leipzig 2014]] day 3: http://www.w3.org/2014/04/09-svg-minutes.html
#   ** 1. SVG sizing
#   ** 2. Lunch plans

use strict;

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

my %topics = ();
my %minutes = ();
my $lastMinutes;
my $lastTopic;

# Step -1: Get the contents of the [[Topic database]] page.

my $mode = 'looking-for-topics';
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
      $lastTopic = $1;
      $topics{$lastTopic} = { title => $lastTopic, description => '', entries => [] };
    } elsif ($_ eq '== Meetings ==') {
      $mode = 'meetings';
      next;
    } elsif (/^==/) {
      die "unexpected input line '$_' in mode $mode";
    } else {
      if (defined $lastTopic) {
        $topics{$lastTopic}{description} .= "$_\n";
      }
    }
  } elsif ($mode eq 'meetings') {
    if (/^\* ([0-9-]+)\s*(.*): (.+)$/) {
      my $date = $1;
      my $title = $2;
      my $link = $3;
      $title = 'Teleconference' unless $title ne '';
      $lastMinutes = $link;
      $minutes{$link} = { title => $title, date => $date, topics => [] };
    } elsif (/^\*\* (?:(\d+)\. )(.*)/) {
      my $index = $1;
      my @topicNames = split(/\s\|\s/, $2);
      $lastTopic = { minutes => $lastMinutes, index => $index, topicNames => [@topicNames], resolutions => [] };
      if (defined $index) {
        $lastTopic->{link} = "$lastMinutes#item" . sprintf('%02d', $index);
        $lastTopic->{index} = $index;
      } else {
        $lastTopic->{link} = $lastMinutes;
        $lastTopic->{index} = -1;
      }
      push(@{$minutes{$lastMinutes}{topics}}, $lastTopic);
      for (@topicNames) {
        $topics{$_} = { title => $_, description => '', entries => [] } unless defined $topics{$_};
        push(@{$topics{$_}{entries}}, $lastTopic);
      }
    } elsif (/^\*\*\* RESOLUTION: (.*)/) {
      push(@{$lastTopic->{resolutions}}, $1);
    } elsif (/^\s*$/) {
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
  my $topic = $topics{$_};
  print FH "== $topic->{title} ==\n\n";
  my $desc = $topic->{description};
  $desc =~ s/^\n+//;
  $desc =~ s/\n+$//;
  if ($desc ne '') {
    print FH "$desc\n\n";
  }
  for my $entry (sort { $minutes{$b->{minutes}}{date} cmp $minutes{$a->{minutes}}{date} } @{$topics{$_}{entries}}) {
    my $linkName = "$minutes{$entry->{minutes}}{title} ($minutes{$entry->{minutes}}{date})";
    print FH "* [$entry->{link} $linkName]\n";
    for my $res (@{$entry->{resolutions}}) {
      print FH "** RESOLUTION: $res\n";
    }
  }
  print FH "\n";
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
       '--data', "wpName=$wpName&wpPassword=$wpPassword&wpDomain=$wpDomain&wpRemember=$wpRemember&wpLoginattempt=$wpLoginattempt&wpLoginToken=$wpLoginToken",
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
