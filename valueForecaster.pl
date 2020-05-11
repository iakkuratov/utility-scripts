#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use DBI;

my $PI=3.1415926535;
my $id=23773;

my $FOR_HOST='';
my $FOR_DB='';
my $FOR_USR='';
my $FOR_PWD='';

my $ZAB_HOST='';
my $ZAB_DB='';
my $ZAB_USR='';
my $ZAB_PWD='';

test();

#test
sub test{
  my @x;
  my @y;
  my $interCoef=5;
  
  #get data
  my $dbh_zab=DBI->connect("DBI:mysql:database=$ZAB_DB;host=$ZAB_HOST", $ZAB_USR, $ZAB_PWD) 
     or die "Error connecting to database $ZAB_DB";
   # clock>unix_timestamp(now())-7*24*60*60
  my $sth = $dbh_zab->prepare('SELECT DAYOFWEEK(FROM_UNIXTIME(clock)) dow,clock,value FROM history_uint WHERE clock>1484658002-28*24*60*60 and itemid='.$id) or die "prepare statement failed: $dbh_zab->errstr()";
  $sth->execute();
  my $first=0;
  while (my $ref = $sth->fetchrow_hashref()) {
    if ($first==0){$first=$ref->{'clock'};}
    push(@x,$ref->{'clock'});
    push(@y,$ref->{'value'});
  }
  $sth->finish();
  $dbh_zab->disconnect;
  
  #process data
  my @xnew=correctX(\@x,-1*$first,1/41250);
  my ($a,$b)=getInterpolateCoeficents(\@xnew,\@y,$interCoef);
  my @gx=getValuesByCoeficents($a,$b,\@xnew);
  my $sigma=getStandartDeviation(substractArray(\@y,\@gx));
  
  #save data
  my $dbh_for=DBI->connect("DBI:mysql:database=$FOR_DB;host=$FOR_HOST", $FOR_USR, $FOR_PWD) 
     or die "Error connecting to database $FOR_DB";
  
  $sth = $dbh_for->prepare("DELETE FROM interpolateCoeficentsA WHERE itemid=$id") or die "prepare statement failed: $dbh_for->errstr()";
  $sth->execute();
  for (my $i=0;$i<scalar @$a;$i++){
    $sth = $dbh_for->prepare("INSERT INTO interpolateCoeficentsA(itemid,coefid,value) VALUES ($id,$i,@$a[$i])") or die "prepare statement failed: $dbh_for->errstr()";
    $sth->execute();
  }
  $sth = $dbh_for->prepare("DELETE FROM interpolateCoeficentsB WHERE itemid=$id") or die "prepare statement failed: $dbh_for->errstr()";
  $sth->execute();
  for (my $i=0;$i<scalar @$b;$i++){
    $sth = $dbh_for->prepare("INSERT INTO interpolateCoeficentsB(itemid,coefid,value) VALUES ($id,$i,@$b[$i])") or die "prepare statement failed: $dbh_for->errstr()";
    $sth->execute();
  }
  $sth = $dbh_for->prepare("DELETE FROM interpolateError WHERE itemid=$id") or die "prepare statement failed: $dbh_for->errstr()";
  $sth->execute();
  $sth = $dbh_for->prepare("INSERT INTO interpolateError(itemid,value) VALUES ($id,$sigma)") or die "prepare statement failed: $dbh_for->errstr()";
  $sth->execute();
  $dbh_for->disconnect;
}
sub correctX{
  my @result;
  foreach my $val(@{$_[0]}){
    push(@result,($val+$_[1])*$_[2]);
  }
  return @result;
}
#Interpolator
#input: href for x array, href for y array, interpolateion level integer
sub getInterpolateCoeficents{
  my @x=@{$_[0]};
  my @y=@{$_[1]};
  my $level=$_[2];
  
  my $count=scalar @x;
  if (!(scalar @y==$count)){debug("different size of x and y arrays");}
  
  my (@a,@b);
  $a[0]=getArraySum(\@y)/$count;
  $b[0]=0;
  for (my $i=1;$i<=$level;$i++){
    for (my $j=0;$j<$count-1;$j++){
      $a[$i]+=$y[$j]*cos($i*$x[$j]);
      $b[$i]+=$y[$j]*sin($i*$x[$j]);
    }
    $a[$i]*=2/$count;
    $b[$i]*=2/$count;
  }
  return (\@a,\@b);
}

sub getValuesByCoeficents{
  my @a=@{$_[0]};
  my @b=@{$_[1]};
  my @x=@{$_[2]};
  
  my @gx;
  for (my $i=0;$i<scalar @x;$i++){
    for (my $j=0;$j<scalar @a;$j++){
      $gx[$i]+=$a[$j]*cos($j*$x[$i])+$b[$j]*sin($j*$x[$i]);
    }
  }
  return @gx;
}

sub getArraySum{
  my $array=shift;
  my $result=0;
  foreach my $value(@$array)
  {
    $result+=$value;
  }
  return $result;
}

sub getStandartDeviation{
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
  return getArraySum(\@_)/($#_+1);
}

sub moveArray{
  my @array=@{$_[0]};
  my $value=$_[1];
  my @result;
  foreach my $val(@array){push (@result,sprintf("%.1f",$val+$value));}
  return @result;
}

sub substractArray{
  my @a=@{$_[0]};
  my @b=@{$_[1]};
  my @result;
  for (my $i=0;$i<scalar @a;$i++){
    push (@result,$a[$i],$b[$i]);
  }
  return @result;
}

sub getJSON{
  my (%hash)=@_;
  my $result="{\n";
  while ( my ($key,$value) = each(%hash)){
    $result.='"'.$key.'": [';
       for (my $i=0; $i<scalar @$value-1;$i++){
        $result.=@$value[$i].","
      }
    $result.=@$value[scalar @$value-1];
    $result.="],\n";
  }
  return substr($result, 0, -2)."\n".'}';
}



sub debug{
  my $msg=shift;
  print "$msg\n";
}
