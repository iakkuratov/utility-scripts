#!/usr/bin/perl
use 5.010;
use strict;
use warnings;
use DBI;
use Math::Complex;
use Parallel::ForkManager;
use Data::Dumper qw(Dumper);

### CONFIG ###
my $folder="/usr/share/cacti/site/rra/";        #path to folder with rra's
my $period = 7;                                 #in days
my $rrdpath = '/usr/bin/rrdtool';               #path to rrdtool
my $maxThreads = 200;                           #maximum nuber of threads avalible for parser
### END CONFIG ###

### DATA MINER ###
my @rras=`find $folder -type f -mtime -1 | grep rrd`;
# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=;host=","", "",{'RaiseError' => 1});

#my $pm = new Parallel::ForkManager($maxThreads);

foreach my $path (@rras)
{
#       $pm->start and next;
        $path=~s/\n//;
        my ($hostId,$rraId) = $path =~/.+\/(.+)\/(.+)\.rrd/;
        my $out=`$rrdpath fetch $path AVERAGE -s end-"$period"days`;
        my @lines = split("\n",$out);
        my @columns = split (" ",$lines[0]);

        my %sources;
        my @line;
        for (my $i = 2; $i<=$#lines-2; $i++){
                @line=split (" ",$lines[$i]);
                for (my $j = 1; $j<=$#line; $j++)
                {
                        $sources{$columns[$j-1]}[$i-2]=$line[$j];
                }

        }

        my $sameRRA = 0; #for nice output

### DATA PROCESSOR ###
        while (my($header,$values)=each %sources)
        {
                my $value = sprintf("%.10g", @{$values}[-1]);
                my ($trendA,$trendB) = getTrend(@{$values});
                #my @trend = getTrendArray($trendA,$trendB,scalar(@{$values}));
                my @avr = getAverageArray(@{$values});
                my @devArr = getDeviationArray(\@avr, \@{$values});
                my $dev = getStandartDeviation(@devArr);
                my $min = $avr[-1]-3*$dev-($value/100);
                my $max = $avr[-1]+3*$dev+($value/100);
                if (($value<$min)||($value>$max))
                {
                        my $graphName="host:$hostId ds:$rraId";
                        if ($sameRRA==0){
                                print "host:$hostId:rra:$rraId\n";$sameRRA=1;

                                my $sth = $dbh->prepare("SELECT cacti.data_local.host_id,cacti.host.description,cacti.data_template_data.name_cache FROM cacti.data_template_data INNER JOIN cacti.data_local ON cacti.data_template_data.local_data_id=cacti.data_local.id INNER JOIN cacti.host ON cacti.data_local.host_id=cacti.host.id WHERE local_data_id=$rraId;");
                                $sth->execute();

                                while (my $ref = $sth->fetchrow_hashref()) {
                                        $graphName = $ref->{'name_cache'};
                                }
                                 $sth->finish();
                        }
                        print "\t$header: min:$min value:$value max:$max\n";
                        `rrdtool graph ./tmp/$rraId.png -a PNG --title='$graphName' --start='-864000' --end='-300' 'DEF:a=$path':'$header':AVERAGE 'LINE1:a#ff0000:$header'`
                }
        }
#       $pm->finish;
}
#$pm->wait_all_children;
$dbh->disconnect();
### REPORT ###
print "\n===========\nDone!\n";
printf("It takes: %.2f sec\n",times);
print "for: ".$#rras." archives";
print "\n===========\n";

### SUBROUTINES ###
sub getTrend
{
        my @t;
        my $a=0;
        my $b=0;
        for (my $i=1; $i<=$#_; $i++){push (@t,$i);}
        my @x2=multiplyArrays(\@_,\@_);
        my $devicentA=$#_*getSum(multiplyArrays(\@_,\@t))-getSum(@_)*getSum(@t);
        my $deviderA=$#_*getSum(@x2)-getSum(@x2);
        if ($deviderA!=0){$a=$devicentA/$deviderA;}
        $b=((getSum(@_)-$a*getSum(@t))/$#_);
        return ($a,$b);
}
sub getTrendArray
{
        my @result;
        my ($a,$b,$count)=@_;
        for (my $i=0; $i<=$count; $i++){push (@result,($a*$i+$b));}
        return @result;
}
sub getAverageArray
{
        my @meanValues;
        my @tempSeson;
        my $counter=0;
        for (my $i = 0; $i<($#_+2)/$period; $i++)
        {
                $counter=$i;
                while ($counter<($#_+1))
                {
                        push(@tempSeson,$_[$counter]);
                        $counter+=($#_+2)/$period;
                }
                if ($period>=4){@tempSeson=removeMinMax(@tempSeson);}
                push(@meanValues,getArithmeticMean(@tempSeson));
                @tempSeson=();
        }
        return @meanValues;
}
sub removeMinMax
{
        my $min=$_[0];
        my $max=$_[0];
        my $imin=0;
        my $imax=0;
        my @result;
        for (my $i=0; $i<$#_+1; $i++)
        {
                if ($_[$i]>$max){$max=$_[$i];$imax=$i;}
                if ($_[$i]<$min){$min=$_[$i];$imin=$i;}
        }
        for (my $i=0; $i<$#_+1; $i++)
        {
                if (($i!=$imax)&&($i!=$imin)){push(@result,$_[$i]);}
        }
        return @result;
}
sub getDeviationArray
{
        my $avr=shift;
        my $dev=shift;
        my @result;
        for (my $i = 0; $i<scalar(@$dev); $i++)
        {
                push(@result,@$avr[$i%(scalar(@$dev)/$period)]-@$dev[$i]);
        }
        return @result;
}
sub getStandartDeviation
{
        my $sum=0;
        my $x_=getArithmeticMean(@_);
        foreach my $value(@_)
        {
                $sum+=($value-$x_)**2;

        }
        return sqrt($sum/($#_+1));
}
sub getArithmeticMean
{
        return getSum(@_)/($#_+1);
}
sub getSum
{
        my $sum=0;
        foreach my $value(@_)
        {
                $sum+=$value;

        }
        return $sum;
}
sub multiplyArrays
{
        my $a=shift;
        my $b=shift;
        my @result;
        my $min=(scalar(@$a)>scalar(@$b))?scalar(@$a):scalar(@$b);
        for(my $i=0; $i<$min-1; $i++)
        {
                push (@result,@$a[$i]*@$b[$i]);
        }
        return @result;
}
