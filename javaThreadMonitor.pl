#!/usr/bin/perl

#####################################################################################
#
#Script for sending java cpu thread statistic to zabbix server using zabbix_sender.
#It reads jstack to get system pids and get statistic from /proc/PARENT/task/PID/stat
#You should set following varibles before use:
#JSTACK_FILE - path to jstack file to read
#ZABBIX_SENDER - path to zabbix_sender executable file
#ZABBIX_SERVER - zabbix server ip or hostname
#
#usege:
#threadMonitor.pl list    - return list of threads and pids for zabbix discovery
#threadMonitor.pl         - send metrics to zabbix server
#
#####################################################################################


use warnings;
use strict;
use Data::Dumper;
use Sys::Hostname;

my $ZABBIX_SENDER="/usr/bin/zabbix_sender";
my $JSTACK_FILE="";
my $ZABBIX_SERVER="";

my $java_pid=`pgrep -f "[C]ommandLineStartup"`;
$java_pid =~ s/[\r\n]+$//;
my $result = "{\"data\":[\n";
my %threads;
my $hostname=hostname;

#get pids and thread names from jstack
foreach my $line (readFile($JSTACK_FILE)){
    if ($line =~ m/\"([\S\d-]+)\".+nid=0x([\da-f]+)/){
        my ($tname,$pid) = ($1,sprintf("%d", hex($2)));
        $tname=~s/\%.+\%$//;
        $threads{$tname}{pid}=$pid;
    }
}

#return discovery list if argument 'lsit' received
if (defined $ARGV[0] && $ARGV[0] eq 'list'){
    foreach (keys %threads){
         $result.=qq(  {"{#TNAME}":"$_", "{#TYPE}":"utime"},\n);
         $result.=qq(  {"{#TNAME}":"$_", "{#TYPE}":"stime"},\n);
    }
    print substr($result, 0, -2)."\n]}\n";
    exit(0);
}

#get metrics from stat files
foreach my $tname (keys %threads){
    my $pid = $threads{$tname}{pid};
    my @file = readFile("/proc/$java_pid/task/$pid/stat");
    if (scalar @file > 0){
        my @stat = split(/ /,$file[0]);
        $threads{$tname}{stime} = $stat[13];
        $threads{$tname}{utime} = $stat[14];
    }else{
        $threads{$tname}{stime} = 0;
        $threads{$tname}{utime} = 0;
    }
}

#format metrics
my $metrics="";
foreach my $tname (keys %threads){
    $metrics.= "$hostname time[$tname\_stime] ".$threads{$tname}{stime}."\n";
    $metrics.= "$hostname time[$tname\_utime] ".$threads{$tname}{utime}."\n";
}

#send stat to zabbix server
my $tmp_file="/tmp/thredStat_".genRandom(8).".tmp";
writeFile($tmp_file,$metrics);
system("$ZABBIX_SENDER -vv -z $ZABBIX_SERVER -i $tmp_file");
unlink $tmp_file or warn "Could not unlink $tmp_file: $!";

###UTILITY SUBS###
sub readFile{
    my $file=shift;
    my @lines;
    if (-e $file){
        open my $handle, '<', $file;
        chomp(@lines = <$handle>);
        close $handle;
    }
    return @lines;
}
sub writeFile{
    my ($file,$text)=@_;
    open(my $fh, '>', $file) or die "Could not open file '$file' $!";
    print $fh $text;
    close $fh;
}
sub genRandom{
    my $count=shift;
    my @chars = ("A".."Z", "a".."z");
    my $string;
    $string .= $chars[rand @chars] for 1..$count;
    return $string;
}
