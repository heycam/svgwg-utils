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

use strict;

my $HOME = $ENV{HOME};
die "\$HOME is not set" unless defined $HOME;
die "\$HOME is not a directory" unless -d $HOME;

my $dir = "$HOME/.svgwg-utils";
unless (-d $dir) {
  mkdir $dir or die "couldn't create $dir";
}

die "could not read $dir/linter" unless -f "$dir/linter";

my @files = ();

open FH, "$dir/linter" or die "could not read ~/.svgwg-utils/linter";
while (<FH>) {
  chomp;
  push @files, $_;
}
close FH;

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

exit if $last_rev eq $this_rev;

mkdir "$dir/.linter-state" unless -d "$dir/.linter-state";

my @errors = ();

for (@files) {
  my $file = $_;
  unless (-f "$dir/.linter-repo/svgwg/$file") {
    print "spec file not found: $file\n";
    next;
  }
  push @errors, split(/\n/, `cd $dir/.linter-repo/svgwg && xmlwf $file`);
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
    my $issues_were = scalar @errors ? 'issue was' : 'issues were';
    my $them = scalar @errors ? 'it' : 'them';
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
