#!/usr/bin/perl -w

# spec-linter.pl
#
# Checks specifications in the SVG WG repository for errors and emails
# the committers who introduced them.
#
# Configuration
# =============
#
# Create a file named ~/.svgwg-utils/linter that has a list of specification
# master files in the SVG WG repostiory to check, one per line.
#
# If a file named ~/.svgwg-utils/linter-ignore exists, then each line is
# taken as a URL that will be skipped when doing broken link checks.

use strict;

use Date::Parse;
use File::Temp 'tempfile';

my $HOME = $ENV{HOME};
die "\$HOME is not set" unless defined $HOME;
die "\$HOME is not a directory" unless -d $HOME;

my $dir = "$HOME/.svgwg-utils";
unless (-d $dir) {
  mkdir $dir or die "couldn't create $dir";
}

die "could not read $dir/linter" unless -f "$dir/linter";

my @files = ();
my %ignore = ();

open FH, "$dir/linter" or die "could not read ~/.svgwg-utils/linter";
while (<FH>) {
  chomp;
  push @files, $_;
}
close FH;

if (-f "$dir/linter-ignore") {
  open FH, "$dir/linter-ignore" or die "could not read ~/.svgwg-utils/linter-ignore";
  while (<FH>) {
    chomp;
    $ignore{$_} = 1;
  }
  close FH;
}

mkdir "$dir/.linter-repo" unless -d "$dir/.linter-repo";
system "cd $dir/.linter-repo && git clone https://github.com/w3c/svgwg" unless -d "$dir/.linter-repo/svgwg";

my $last_rev = `cd $dir/.linter-repo/svgwg && ( git log -1 | grep '^commit ' | head -1 | sed 's/^commit //' )`;
chomp $last_rev;
die "could not get last rev" unless $last_rev =~ /^[0-9a-f]+$/;

system "cd $dir/.linter-repo/svgwg && git pull -q --ff-only";
die if ($? >> 8);

my $this_rev = `cd $dir/.linter-repo/svgwg && ( git log -1 | grep '^commit ' | head -1 | sed 's/^commit //' )`;
chomp $this_rev;
die "could not get this rev" unless $this_rev =~ /^[0-9a-f]+$/;

# exit if $last_rev eq $this_rev;

mkdir "$dir/.linter-state" unless -d "$dir/.linter-state";

my @errors = ();

# first we run xmlwf; if there were no errors, we check links

for (@files) {
  my $file = $_;
  unless (-f "$dir/.linter-repo/svgwg/$file") {
    print "spec file not found: $file\n";
    next;
  }
  push @errors, split(/\n/, `cd $dir/.linter-repo/svgwg && xmlwf $file`);
}

my %spec_dirs = ();

unless (@errors) {
  for (@files) {
    my $dir = `dirname \$(dirname $_)`;
    chomp $dir;
    $spec_dirs{$dir} = 1;
  }
}

mkdir "$dir/.linter-cache" unless -d "$dir/.linter-cache";

my @links = ();
for my $spec_dir (sort keys %spec_dirs) {
  for (split(/\n/, `cd $dir/.linter-repo/svgwg/$spec_dir && make list-external-links`)) {
    my ($file, $line, $col, $href) = /^([^:]+):(\d+):(\d+):(.*)/;
    next if exists $ignore{$href};
    my $dir = $spec_dir eq '.' ? 'master' : "$spec_dir/master";
    while ($file =~ /^\.\.\//) {
      if ($dir =~ s/\/[^\/]+$//) {
        $file =~ s/^\.\.\///;
      } elsif ($dir eq '') {
        last;
      } else {
        $file =~ s/^\.\.\///;
        $dir = '';
      }
    }
    $file = $dir eq '' ? $file : "$dir/$file";
    push @links, "$file:$line:$col:$href";
  }
  push @errors, split(/\n/, `cd $dir/.linter-repo/svgwg/$spec_dir && make lint 2>&1`);
}

sub percent_encode {
  my $c = shift;
  return '%' . sprintf('%02x', ord($c));
}

sub escape_url {
  my $s = shift;
  $s =~ s{([^A-Za-z0-9._~:/?#@!\$&()*+,;=-])}{percent_encode($1)}ge;
  return $s;
}

my %links_without_refs = ();
my %links_with_refs = ();
for (@links) {
  my ($file, $line, $col, $href) = /^([^:]+):(\d+):(\d+):(.*)/;
  next if $href =~ /log\.csswg\.org/;
  $href = escape_url($href);
  if ($href =~ /(.*)#(.*)/) {
    $links_with_refs{$1} = { } unless exists $links_with_refs{$1};
    $links_with_refs{$1}{$2} = { } unless exists $links_with_refs{$1}{$2};
    $links_with_refs{$1}{$2}{"$file:$line:$col"} = 1;
  } else {
    $links_without_refs{$href} = { } unless exists $links_without_refs{$href};
    $links_without_refs{$href}{"$file:$line:$col"} = 1;
  }
}

sub escape_fn_char {
  my $c = shift;
  return '_' . sprintf('%02x', ord($c));
}

sub escape_fn {
  my $s = shift;
  $s =~ s/([^a-z0-9])/escape_fn_char($1)/ge;
  return $s;
}

sub read_headers {
  my $fh = shift;
  my $status_line = <$fh>;
  my %headers = ();
  if ($status_line =~ /^HTTP\S+ (\d+)/) {
    $headers{_status} = $1;
    while (<$fh>) {
      chomp;
      s/\x0D$//g;
      last if $_ eq '';
      last unless /^([^:]+):\s*(.*)/;
      $headers{lc $1} = $2;
    }
  }
  return %headers;
}

sub curl_error {
  my $n = shift;
  if ($n == 3) {
    return "bad URL";
  } elsif ($n == 6) {
    return "could not resolve host";
  } elsif ($n == 7) {
    return "could not connect to host";
  } elsif ($n == 28) {
    return "timeout";
  } elsif ($n) {
    return "curl error " . $n;
  }
  return undef;
}

sub fetch {
  my $url = shift;
  my $method = shift;
  die unless $method eq 'HEAD' || $method eq 'GET';
  my $options = '-s -m 30 -H "Accept: text/html,*/*;q=0.9"';
  $options .= $method eq 'HEAD' ? ' -I' : ' -i';
  my $cache_good_result_even_without_known_freshness = shift;
  my $key = escape_fn($url);
  my $filename = "$dir/.linter-cache/$method-$key";
  my $get = !-f $filename || -z $filename;
  my $redirects = 0;
  my $loops = 0;
  my $allow_unfresh = 0;
  my $new_fragment = undef;
  for (;;) {
    return (undef, "too many loops") if ++$loops > 10;
    my $got = 0;
    if ($get) {
      print "curl $options '$url' > $filename\n";
      system "curl $options '$url' > $filename";
      if ($? >> 8) {
        return (undef, curl_error($? >> 8));
      } elsif (-z $filename) {
        return (undef, "no output from curl");
      }
      $get = 0;
      $got = 1;
      $allow_unfresh = 1;
    } else {
      $allow_unfresh = 0;
    }
    my $fh;
    open $fh, $filename;
    my %headers = read_headers($fh);
    return (undef, "could not parse output from curl") unless defined $headers{_status};
    my $expires;
    my $known_fresh = 0;
    if (!$allow_unfresh &&
        exists $headers{expires} &&
        defined($expires = str2time($headers{expires}))) {
      if ($expires < time) {
        $get = 1;
        next;
      }
      $known_fresh = 1;
    }
    # cached good results are used
    if (($known_fresh || $cache_good_result_even_without_known_freshness) &&
        $headers{_status} >= 200 && $headers{_status} <= 299) {
      local $/;
      my $contents = <$fh>;
      return ($headers{_status}, undef, $contents);
    }
    # cached bad results are not
    if ($headers{_status} >= 300 && $headers{_status} <= 399) {
      return (undef, 'HTTP 3xx code without Location') unless exists $headers{location};
      return (undef, "too many redirects") if ++$redirects >= 5;
      my $location = $headers{location};
      $location =~ s/#(.*)//;
      if ($location =~ /^\//) {
        my ($host_part) = $url =~ m{^(https?://[^/]+)};
        return (undef, "bad URL") unless defined $host_part;
        $url = $host_part . escape_url($location);
      } else {
        $url = escape_url($location);
      }
      $get = 1;
      next;
    }
    if ($got) {
      local $/;
      my $contents = <$fh>;
      return ($headers{_status}, undef, $contents);
    }
    $get = 1;
  }
}

sub cached_head {
  my $url = shift;
  return fetch($url, 'HEAD', 1);
}

sub cached_get {
  my $url = shift;
  return fetch($url, 'GET', 0);
}

for my $url (sort keys %links_with_refs) {
  my ($status, $reason, $contents) = cached_get($url);
  my $fragments = $links_with_refs{$url};
  if (defined $status && $status >= 400 && $status <= 499) {
    $reason = "HTTP status $status";
  }
  if (defined $reason) {
    for my $fragment (keys %$fragments) {
      my $locations = $fragments->{$fragment};
      for (keys %$locations) {
        push @errors, "$_: broken link $url ($reason)";
      }
    }
    if (exists $links_without_refs{$url}) {
      for (keys %{$links_without_refs{$url}}) {
        push @errors, "$_: broken link $url ($reason)";
      }
    }
    delete $links_without_refs{$url};
    next;
  }

  for my $fragment (keys %$fragments) {
    unless ($contents =~ /\s(?:(?i)id)=(?:$fragment|'$fragment'|"$fragment")(?:\s|>)/ ||
            $contents =~ /<(?:[Aa])\s+[^>]*(?:(?i)name)=(?:$fragment|'$fragment'|"$fragment")/) {
      my $locations = $fragments->{$fragment};
      for (keys %$locations) {
        push @errors, "$_: broken link $url (fragment $fragment not found)";
      }
    }
  }
}

for my $url (sort keys %links_without_refs) {
  my ($status, $reason) = cached_head($url);
  if (defined $status && $status >= 400 && $status <= 499) {
    $reason = "HTTP status $status";
  }
  if (defined $reason) {
    for (keys %{$links_without_refs{$url}}) {
      push @errors, "$_: broken link $url ($reason)";
    }
  }
}

# Now do validation.

sub erase {
  my $s = shift;
  $s =~ s/[^\n]/ /g;
  return $s;
}

for my $fn (@files) {
  local $/;
  open FH, "$dir/.linter-repo/svgwg/$fn";
  my $content = <FH>;
  close FH;
  $content =~ s/(<\?xml.*?\?>)/erase($1)/se;
  $content =~ s/<!DOCTYPE.*?>/<!DOCTYPE html>/s;
  $content =~ s/(xmlns:.*?=(".*?"|'.*?'))/erase($1)/gse;
  $content =~ s/(<edit:[a-z]+\s*.*?>)/erase($1)/gse;
  $content =~ s/(<\/edit:[a-z]+>)/erase($1)/gse;
  $content =~ s/(\sedit:[a-z]+=(".*?"|'.*?'))/erase($1)/gse;
  $content =~ s/(<!\[CDATA\[.*?\]\]>)/erase($1)/gse;
  $content =~ s/(href=["'])(\[.*?\])/$1 . erase($2)/gse;
  my ($fh, $filename) = tempfile();
  print $fh $content;
  close $fh;
  for (split(/\n/, `curl -s -H "Content-Type: text/html; charset=utf-8" --data-binary \@$filename http://validator.w3.org/nu/?out=gnu`)) {
    push @errors, "$fn:$_";
  }
  unlink $filename;
}

my %culprits = ();
if (-f "$dir/.linter-state/culprits") {
  open FH, "$dir/.linter-state/culprits";
  while (<FH>) {
    chomp;
    $culprits{$_} = 1;
  }
  close FH;
}

if (@errors) {
  open FH, "cd $dir/.linter-repo/svgwg && git log --format='%ae' $last_rev..$this_rev |";
  while (<FH>) {
    chomp;
    $culprits{$_} = 1 if /@/;
  }
  close FH;
  if (%culprits) {
    my @args = ('mail', '-r', 'SVG Working Group Apprentice <cam+svgwg-apprentice@mcc.id.au>', '-s', '[svgwg] spec issues');
    push @args, '-c', 'cam@mcc.id.au' unless exists $culprits{'cam@mcc.id.au'};
    if (0) {
      push @args, 'cam@mcc.id.au';
    } else {
      push @args, sort keys %culprits;
    }
    open FH, '|-', @args;
    if (0) {
      for (sort keys %culprits) {
        print FH "(to $_)\n";
      }
    }
    my $issues_were = scalar(@errors) == 1 ? 'issue was' : 'issues were';
    my $them = scalar(@errors) == 1 ? 'it' : 'them';
    print FH "The following $issues_were found while linting specs in the SVG WG\n";
    print FH "repository at revision $this_rev:\n\n";
    for (@errors) {
      print FH "  $_\n";
    }
    print FH "\nPlease attend to $them at your earliest convenience!\n";
    close FH;
  }
  open FH, "> $dir/.linter-state/culprits";
  for (sort keys %culprits) {
    print FH "$_\n";
  }
  close FH;
} else {
  if (%culprits) {
    open FH, "cd $dir/.linter-repo/svgwg && git log --format='%ae' $last_rev..$this_rev |";
    while (<FH>) {
      chomp;
      $culprits{$_} = 1 if /@/;
    }
    close FH;
    my @args = ('mail', '-r', 'SVG Working Group Apprentice <cam+svgwg-apprentice@mcc.id.au>', '-s', '[svgwg] spec issues resolved');
    push @args, '-c', 'cam@mcc.id.au' unless exists $culprits{'cam@mcc.id.au'};
    if (0) {
      push @args, 'cam@mcc.id.au';
    } else {
      push @args, sort keys %culprits;
    }
    open FH, '|-', @args;
    if (0) {
      for (sort keys %culprits) {
        print FH "(to $_)\n";
      }
    }
    print FH "The spec issues I mentioned have been resolved.  Thank you! :-)\n";
    close FH;
    open FH, "> $dir/.linter-state/culprits";
    close FH;
  }
}
