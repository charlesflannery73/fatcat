#!/usr/bin/perl

use warnings;
use strict;

use Archive::Zip;
use Data::Dumper;
use XML::Simple;
use File::MimeInfo;

# globals
my $config_file;
my $config;
my @zip_dirs;
my $working_dir;
my $logdir;
my $poll;
my $verbose = 'n';


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

# subroutines
sub usage() {
  print "Usage:\n$0 fatcat_distributor.xml\n";
  exit(0);
}


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

  $poll = $config->{'poll'};
  $logdir = $config->{'logdir'};
  $verbose = $config->{'log_verbose'};

  my $zip_dir_flag = 0;
  foreach my $zip_dir (@{$config->{'zip_dir'}}) {
    if (!-d $zip_dir) {
      print "$zip_dir not found\n";
      exit(1);
    }
    push (@zip_dirs, $zip_dir);
    $zip_dir_flag = 1;
  }

  if (!$zip_dir_flag) {
    print "zip_dir not found\n";
    exit(1);
  }

  $working_dir = $config->{'working_dir'};
  if (!-d $working_dir) {
    print "working_dir $working_dir not found\n";
    exit(1);
  }

  log_text("Starting new instance\n");

  #print Dumper $config;

}


sub make_dirs() {
  foreach my $agent (@{$config->{'agent'}}) {
    mkdir $agent->{'dir'};
    if (!-d $agent->{'dir'}) {
      print "$agent->{'dir'} not found\n";
      exit(1);
    }
  }
}


sub distribute($){
  my $file = shift;
  chomp $file;
  foreach my $agent (@{$config->{'agent'}}) {
    my $include = 0;
    foreach my $inclusion ($agent->{'include'}) {
      if (defined $inclusion->{'file_ext'}) {
        my $ext = $file;
        $ext =~ s/.*\.//;
        if (($ext eq $inclusion->{'file_ext'}) or ($inclusion->{'file_ext'} eq "*")) {
          $include = 1;
          last;
        }
      }
      if (defined $inclusion->{'mime_type'}) {
        my $mime_type = mimetype($file);
        if ($mime_type eq $inclusion->{'mime_type'}) {
          $include = 1;
          last;
        }
      }
    }
    if ($include) {
      my $new_link = $file;
      $new_link =~ s/.*\///;
      $new_link = "$agent->{'dir'}/$new_link";
      link $file, $new_link;
      log_text("linking $file to $new_link\n");
    }
  }
}

sub log_text($){
  my $log = shift;
  my $etime = gmtime();
  my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
  my $month = $month_lookup{$mon};
  $log = "$year-$month-$day $time $log";
  my $log_file = "$logdir/$year-$month-$day.log";
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

sub log_error($){
  my $log = shift;
  my $etime = gmtime();
  my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
  my $month = $month_lookup{$mon};
  $log = Dumper $log;
  $log = "$year-$month-$day $time\n$log";
  my $log_file = "$logdir/$year-$month-$day.error";
  open(FILE, ">>$log_file") or die("Unable to open $log_file");
  print FILE $log;
  close(FILE);
}


#__MAIN__

get_config();
make_dirs();

while (1) {
  my @zip_files;
  foreach my $zip_dir (@zip_dirs) {
    my @list = glob ("$zip_dir/*.zip");
    @zip_files = (@zip_files, @list);
  }
  foreach my $file (@zip_files) {
    log_verbose("found zip file $file\n");
    my $zip = Archive::Zip->new( $file );
    my @members = $zip->members();
    foreach my $member (@members) {
      if ($member->isDirectory) {
        next;
      }
      my $extract_name = $member->fileName;
      $extract_name =~ s/.*\///;
      $extract_name = "$working_dir/$extract_name";
      $member->extractToFileNamed($extract_name);
      log_verbose("extracting $extract_name\n");
      if (-e $extract_name) {
        distribute($extract_name);
        unlink $extract_name;
      } else {
        log_error("$extract_name not found\n");
        exit(1);
      }
    }
    unlink $file;
  }
  log_verbose("sleeping for $poll seconds\n");
  sleep($poll);
}

