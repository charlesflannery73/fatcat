#!/usr/bin/perl

use strict;
use warnings;

use XML::Simple;

my $config_file;
my $config;
my $agent_name;
my $poll;
my $working_dir;
my $alert_dir;
my $log_dir;
my $verbose = "n";

my %month_lookup = (
    Jan => "01",
    Feb => "02",
    Mar => "03",
    Apr => "04",
    May => "05",
    Jun => "06",
    Jul => "07",
    Aug => "08",
    Sep => "09",
    Oct => "10",
    Nov => "11",
    Dec => "12"
);


sub get_config() {
  if (not defined $ARGV[0]) {
    print "Please provide the config filename\n";
    usage();
  }

  $config_file = $ARGV[0];

  if (!-e $config_file) {
    print "can't find config file $config_file\n";
    usage();
  }

  $config = XMLin($config_file);

  $agent_name = $config->{'agent_name'};
  $poll = $config->{'poll'};
  $working_dir = $config->{'working_dir'};
  $log_dir = $config->{'log_dir'};
  $alert_dir = $config->{'alert_dir'};
  $verbose = $config->{'verbose'};
 
  log_text("Starting new instance\n");
}

# subroutines
sub usage() {
  print "Usage:\n$0 config_file\n";
  exit(0);
}

sub log_text($){
  my $log = shift;
  my $etime = gmtime();
  my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
  my $month = $month_lookup{$mon};
  $log = "$year-$month-$day $time $agent_name: $log";
  my $log_file = "$log_dir/$year-$month-$day.log";
  open(FILE, ">>$log_file") or die("Unable to open $log_file");
  print FILE $log;
  close(FILE);
}

sub log_verbose($){
  my $log = shift;
  if($verbose eq 'y') {
    log_text($log);
  }
}

sub log_alert($){
  my $log = shift;
  my $etime = gmtime();
  my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
  my $month = $month_lookup{$mon};
  $log = "$year-$month-$day $time $agent_name: $log";
  my $log_file = "$alert_dir/$year-$month-$day.alert";
  open(FILE, ">>$log_file") or die("Unable to open $log_file");
  print FILE $log;
  close(FILE);
}

#main

get_config();

while ( 1 ) {
  # batch the files for speed
  my @files = glob("$working_dir/*");
  if (@files) {
    my $list = join(" ", @files);
    my @results = `clamscan --no-summary $list`;
    foreach my $result (@results) {
      if ($result !~ /OK$/) {
        log_alert($result);
        log_text($result);
      } else {
        log_verbose($result);
      }
    }
    foreach my $file (@files) {
      log_verbose("deleting $file\n");
      unlink($file);
    }
  } else {
    log_verbose("No files found\n");
  }
  log_verbose("Sleeping for $poll seconds\n");
  sleep($poll);
}

