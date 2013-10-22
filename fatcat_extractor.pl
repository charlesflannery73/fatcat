#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use XML::Simple;


# globals
my $config_file;
my $config;
my $interval;
my $lag;
my $host;
my $port;
my $user;
my $password;
my $bookmark_file;
my $bookmark;
my $logdir;
my $zipdir;
my $poll;
my $verbose = 'n';
my $log_json = 'n';

my $include_mime_type = 0;
my $include_magic_type = 0;
my $include_extension_type = 0;
my $exclude_mime_type = 0;
my $exclude_magic_type = 0;
my $exclude_extension_type = 0;
my $including = 0;
my $excluding = 0;
my $filtering = 0;

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
  print "Usage:\n$0 config_file\n";
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

  $config = XMLin($config_file, ForceArray => ['extension_type', 'magic_type', 'mime_type', 'include_solera_type']);

  #print Dumper $config;

  $interval = $config->{'interval'};
  $lag = $config->{'lag'};
  $user = $config->{'user'};
  $password = $config->{'password'};
  $host = $config->{'host'};
  $logdir = $config->{'logdir'};
  $zipdir = $config->{'zipdir'};
  $poll = $config->{'poll'};
  $port = $config->{'port'};
  $bookmark_file = $config->{'bookmark_file'};
  $verbose = $config->{'log_verbose'};
  $log_json = $config->{'log_json'};
  open(FILE, $bookmark_file) or die("Unable to open $bookmark_file");
  $bookmark = <FILE>;
  chomp $bookmark;
  close(FILE);
  if ($bookmark !~ /^\d{10}$/) {
    print "bookmark not valid\n";
    usage();
  }

  log_text("Starting new instance\n");

  # set flags if filtering

  if ($config->{'include'}->{'mime_type'}) {
    $include_mime_type = 1;
    log_verbose("include mime type filtering flag on\n");
  }
  if ($config->{'include'}->{'magic_type'}) {
    $include_magic_type = 1;
    log_verbose("include magic type filtering flag on\n");
  }
  if ($config->{'include'}->{'extension_type'}) {
    $include_extension_type = 1;
    log_verbose("include extension type filtering flag on\n");
  }
  if ($config->{'exclude'}->{'mime_type'}) {
    $exclude_mime_type = 1;
    log_verbose("exclude mime type filtering flag on\n");
  }
  if ($config->{'exclude'}->{'magic_type'}) {
    $exclude_magic_type = 1;
    log_verbose("exclude magic type filtering flag on\n");
  }
  if ($config->{'exclude'}->{'extension_type'}) {
    $exclude_extension_type = 1;
    log_verbose("exclude extension type filtering flag on\n");
  }
  $including = $include_mime_type | $include_magic_type | $include_extension_type;
  $excluding = $exclude_mime_type | $exclude_magic_type | $exclude_extension_type;
  $filtering = $including | $excluding;

  if ($including and $excluding) {
    print "Can't both include and exclude";
    exit(1);
  }


  my $logged_config = Dumper $config;
  log_verbose("$logged_config\n");
}


sub get_extraction_list_ids() {
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-list.json?");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $decoded_json = from_json ($page->decoded_content);
  log_json($decoded_json);
  return($decoded_json);
}

sub delete_extraction($) {
  my $id = shift;
  log_verbose("deleting old search id $id\n");
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-delete.json?search_id=$id");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $decoded_json = from_json ($page->decoded_content);
  log_json($decoded_json);
  return($decoded_json);
}


sub start_extraction($$) {
  my $start = shift;
  my $end = shift;
  my $filetypes_string;
  foreach my $solera_type (@{$config->{'include_solera_type'}}){
    $filetypes_string .= "&advanced_options[filetype][]=" . $solera_type;
  }
  if (!$filetypes_string){
    $filetypes_string = "&advanced_options[filetype][]=ALL";
  }
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-start.json?path=/timespan/$start\_$end/$filetypes_string");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $decoded_json = from_json($page->decoded_content);
  log_json($decoded_json);
  return($decoded_json);
}


sub get_extraction_status($) {
  my $id = shift;
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-status.json?search_id=$id");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $decoded_json = from_json($page->decoded_content);
  log_json($decoded_json);
  return $decoded_json;
}


sub get_extraction_results($) {
  my $id = shift;
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-results.json?search_id=$id&result_type=detail&page=1&pageSize=1000");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $decoded_json = from_json($page->decoded_content);
  log_json($decoded_json);
  return $decoded_json;
}


sub get_all_artifacts($) {
  my $id = shift;
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-artifacts?search_id=$id");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $out_file = "$zipdir/search_$id.zip";
  log_verbose("writing $out_file\n");
  open(OUT_FILE, ">$out_file.tmp") or die("Unable to open file");
  print OUT_FILE $page->content;
  close(OUT_FILE);
  rename ("$out_file.tmp",$out_file); 
}


sub get_solera_time($) {
  my $epoch = shift;
  my $etime = gmtime($epoch);
  my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
  my $month = $month_lookup{$mon};
  if (length($day) eq 1) {
    $day = "0$day";
  }
  my $solera_time = "$year-$month-$day" . "T" . "$time";
  return $solera_time;
}


sub get_single_artifacts($$$) {
  my $search_id = shift;
  my $artifact_string= shift;
  my $suffix = shift;
  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new( GET => "http://$host/ws/deepsee-extraction-artifacts?search_id=$search_id$artifact_string");
  $req->authorization_basic( $user, $password );
  $ua->credentials("$host:$port", "Solera", $user, $password);
  my $page = $ua->request( $req );
  if (!$page->is_success) {
    die $page->status_line;
  }
  my $out_file = "$zipdir/search_$search_id\_$suffix.zip";
  log_verbose("writing $out_file\n");
  open(OUT_FILE, ">$out_file.tmp") or die("Unable to open file");
  print OUT_FILE $page->content;
  close(OUT_FILE);
  rename("$out_file.tmp",$out_file);
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

sub log_json($){
  my $log = shift;
  if($log_json eq 'y') {
    my $etime = gmtime();
    my ($weekday, $mon, $day, $time, $year) = split (/ +/, $etime);
    my $month = $month_lookup{$mon};
    $log = Dumper $log;
    $log = "$year-$month-$day $time\n$log";
    my $log_file = "$logdir/$year-$month-$day.json";
    open(FILE, ">>$log_file") or die("Unable to open $log_file");
    print FILE $log;
    close(FILE);
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

while (1) {
  my $start_time = get_solera_time($bookmark);
  my $end_time = get_solera_time($bookmark+$interval-1);

  # sleep if the request is about to include the future or the lag period (give Solera a change to classify the traffic)
  if ($bookmark+$interval+$lag > time) {
    my $delay = $bookmark + $interval + $lag - time + 1;
    log_text("delaying $delay seconds\n");
    my $current_time = time;
    log_verbose("current time $current_time, query end time $bookmark + $interval, lag period $lag\n");
    sleep($delay);
  }

  my $result = get_extraction_list_ids();
  foreach my $search (@{$result->{'response'}->{'searches'}}) {
    delete_extraction($search->{'id'});
  }

  my $id;
  my $status;
  while (1) { #loop until this time block is completed
    $result = start_extraction($start_time, $end_time);
    $id = $result->{'response'}->{'id'};
    log_text("new search id - $id - $start_time to $end_time\n");
    sleep($poll);
    $status = get_extraction_status($id);
    log_verbose("id=$id,status=$status->{'response'}->{'status'},percentage=$status->{'response'}->{'percentage'},nummatched=$status->{'response'}->{'nummatched'}\n");

    while (1) { #loop until this search is completed
      if ($status->{'response'}->{'percentage'} eq '100') {
        last;
      } else {
        sleep($poll);
        $status = get_extraction_status($id);
        log_verbose("id=$id,status=$status->{'response'}->{'status'},percentage=$status->{'response'}->{'percentage'},nummatched=$status->{'response'}->{'nummatched'}\n");
      }
    }
    if ($status->{'response'}->{'status'} eq 'Finished') {
      last;
    } else {
      delete_extraction($id);
    }
  }
  if ($status->{'response'}->{'nummatched'} eq 0) {
    delete_extraction($id);
    $bookmark = $bookmark + $interval;
    open(FILE, ">$bookmark_file") or die("Unable to open $bookmark_file");
    print FILE $bookmark;
    close(FILE);
    next;
  }

  if ($filtering) {
    my $artifact_string;  #&artifact_ids[]=123&artifact_ids[]=124
    my $batch_count = 0;  # to prevent the url being too long
    my $suffix = 0;
    my $results = get_extraction_results($id);
    foreach my $result (@{$results->{'response'}->{'results'}}) {
      if ($batch_count > 9) {
        get_single_artifacts($id,$artifact_string,$suffix);
        $batch_count = 0;
        $artifact_string = "";
      }
      $suffix++;
      my $match = 0;
      if ($including){
        if ($include_mime_type){
          foreach my $mime_config (@{$config->{'include'}->{'mime_type'}}) {
            if ($mime_config eq $result->{'mime_type'}) {
              log_verbose("including search_id=$id artifact_id=$result->{'id'}, $result->{'mime_type'}\n");
              $artifact_string .= "&artifact_ids[]=$result->{'id'}";
              $batch_count++;
              $match++;
              last;
            }
          }
          if ($match) {next;}
        }
        if ($include_magic_type){
          foreach my $magic_config (@{$config->{'include'}->{'magic_type'}}) {
            if ($magic_config eq $result->{'magic_type'}) {
              log_verbose("including search_id=$id artifact_id=$result->{'id'}, $result->{'magic_type'}\n");
              $artifact_string .= "&artifact_ids[]=$result->{'id'}";
              $batch_count++;
              $match++;
              last;
            }
          }
          if ($match) {next;}
        }
        if ($include_extension_type){
          foreach my $extension_config (@{$config->{'include'}->{'extension_type'}}) {
            if ($extension_config eq $result->{'extension'}) {
              log_verbose("including search_id=$id artifact_id=$result->{'id'}, $result->{'extension'}\n");
              $artifact_string .= "&artifact_ids[]=$result->{'id'}";
              $batch_count++;
              $match++;
              last;
            }
          }
          if ($match) {next;}
        }
        log_verbose("not including search_id=$id artifact_id=$result->{'id'},extension=$result->{'extension'},mime_type=$result->{'mime_type'},magic_type=$result->{'magic_type'}\n");
      } else { #excluding
        if ($exclude_mime_type){
          foreach my $mime_config (@{$config->{'exclude'}->{'mime_type'}}) {
            if ($mime_config eq $result->{'mime_type'}) {
              log_verbose("excluding search_id=$id artifact_id=$result->{'id'}, $result->{'mime_type'}\n");
              $match = 1;
              last;
            }
          }
          if ($match) {next;}
        }
        if ($exclude_magic_type){
          foreach my $magic_config (@{$config->{'exclude'}->{'magic_type'}}) {
            if ($magic_config eq $result->{'magic_type'}) {
              log_verbose("excluding search_id=$id artifact_id=$result->{'id'}, $result->{'magic_type'}\n");
              $match = 1;
              last;
            }
          }
          if ($match) {next;}
        }
        if ($exclude_extension_type){
          foreach my $extension_config (@{$config->{'exclude'}->{'extension_type'}}) {
            if ($extension_config eq $result->{'extension'}) {
              log_verbose("excluding search_id=$id artifact_id=$result->{'id'}, $result->{'extension'}\n");
              $match = 1;
              last;
            }
          }
          if ($match) {next;}
        }
        log_verbose("not excluding search_id=$id artifact_id=$result->{'id'},extension=$result->{'extension'},mime_type=$result->{'mime_type'},magic_type=$result->{'magic_type'}\n");
        $artifact_string .= "&artifact_ids[]=$result->{'id'}";
        $batch_count++;
      }
    }
    if ($artifact_string) {
      get_single_artifacts($id,$artifact_string,$suffix);
    }
  } else {
    get_all_artifacts($id);
  }

  $bookmark = $bookmark + $interval;
  open(FILE, ">$bookmark_file") or die("Unable to open $bookmark_file");
  print FILE $bookmark;
  close(FILE);
}
