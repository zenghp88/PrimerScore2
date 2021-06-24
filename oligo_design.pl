#!/usr/bin/perl -
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use FindBin qw($Bin $Script);
use File::Basename qw(basename dirname);
require "$Bin/path.pm";
require "$Bin/common.pm";

my $BEGIN_TIME=time();
my $version="1.0.0";
#######################################################################################

# ------------------------------------------------------------------
# GetOptions
# ------------------------------------------------------------------
my ($NoSpecificity, $FiterRepeat, $NoFilter);
my ($ftem,$ftem_snp,$fkey,$outdir);
my $para_num = 10;
my $stm = 45;
my $opt_tm=60;
my $opt_tm_probe=70;
our $PATH_PRIMER3;
our $REF_HG19;
my $fdatabases = $REF_HG19;
my $probe;
my $orient; ## oligo orient on template, F: forward, R: reverse, FR: both forward and reverse 
my $ptype = "face-to-face";
my $regions; ## regions: start, end, scale
my $range_len="18,36,2";
GetOptions(
				"help|?" =>\&USAGE,
				"i:s"=>\$ftem,
				"is:s"=>\$ftem_snp,
				"d:s"=>\$fdatabases,
				"r:s"=>\$fdatabases,
				"fr:s"=>\$orient,
				"k:s"=>\$fkey,
				"Probe:s"=>\$probe,
				"NoSpecificity:s"=>\$NoSpecificity,
				"FilterRepeat:s"=>\$FiterRepeat,
				"NoFilter:s"=>\$NoFilter,
				"ptype:s"=>\$ptype,
				"rlen:s"=>\$range_len,
				"opttm:s"=>\$opt_tm,
				"opttmp:s"=>\$opt_tm_probe,
				"rregion:s"=>\$regions,
				"stm:s"=>\$stm,
				"para:s"=>\$para_num,
				"od:s"=>\$outdir,
				) or &USAGE;
&USAGE unless ($ftem and $orient and $fkey);

$outdir||="./";
`mkdir $outdir`	unless (-d $outdir);
$outdir=AbsolutePath("dir",$outdir);
my $oligotm = "$PATH_PRIMER3/src/oligotm";
my ($min_len, $max_len, $scale_len)=split /,/, $range_len;
my %seq;

my $n=0;
my @rregion;
if(defined $regions){
	@rregion = &check_merge_rregion($regions);
}

## get template seq containing snp
my %seq_snp;
if(defined $ftem_snp){
	open(I, $ftem_snp) or die $!;
	$/=">";
	while(<I>){
		chomp;
		next if(/^$/);
		my ($id_info, @line)=split /\n/, $_;
		my $seq = join("", @line);
		my ($id)=split /\s+/, $id_info;
		$seq_snp{$id}=$seq;
	}
}

my %record;
my $pori = $orient=~/F/? "F": "R"; ## FR
## get oligo seq
open(I, $ftem) or die $!;
open(PT, ">$outdir/$fkey.oligo.list") or die $!;
$/=">";
while(<I>){
	chomp;
	next if(/^$/);
	my ($id_info, @line)=split /\n/, $_;
	my $seq = join("", @line);
	my ($id)=split /\s+/, $id_info;
	my ($dstart)=$id_info=~/XS:i:(\d+)/;
	my ($dend)=$id_info=~/XE:i:(\d+)/;
	if(!defined $dstart){
		$dstart = 0;
	}
	if(!defined $dend){
		$dend = 0;
	}
	my $seq_snp = $seq_snp{$id};
	
	## 
	my $tlen = length($seq);
	if(!defined $regions){
		@rregion = (1, $tlen, 1);
	}
	for(my $r=0; $r<@rregion; $r+=3){
		my ($min_dis, $max_dis) = ($rregion[$r], $rregion[$r+1]);
		my $min_p = $min_dis-$dstart>0? $min_dis-$dstart: 0; ## dstart=1
		my $max_p = $max_dis-$dend<$tlen? $max_dis-$dend: $tlen;
		if($max_p < $min_p){
			print "Wrong: max position $max_p < min position $min_p! ($min_dis, $max_dis, $dstart, $dend) Maybe dend (XE:i:$dend) is too large, or -rregion range $regions is too narrow!\n";
			die;
		}
		my $sdis = $rregion[$r+2];
		for(my $p=$min_p; $p<=$max_p; $p+=$sdis){
			$n++;
			my $dn=int($n/1000);
			my $dir = "$outdir/split_$dn";
			`mkdir $dir` unless(-d $dir);
			my $fn=$n%1000;
			open(P, ">$dir/$fkey.oligo.list_$fn") or die $!;
			for(my $l=$max_len; $l>=$min_len; $l-=$scale_len){
				next if(($pori eq "R" && $p+$l>$tlen) || ($pori eq "F" && $p-$l<0));
				my ($oligo, $start, $end)=&get_oligo($id, $p, $l, $seq, $pori); ## $p is end3 position
				next if($oligo=~/N/ || $oligo=~/n/);
				my $id_new = $id."-".$pori."-".$start."-".$end; ##oligos of different length are evalued in oligo_evaluation.pl
				if(exists $record{$id_new}){
					die "Wrong: repeat id new! $id_new $id,$p,$l,$n!\n";
				}
				$record{$id_new}=1;	

				if(defined $FiterRepeat){
					my @match = ($oligo=~/[atcg]/g);
					next if(scalar @match > length($oligo)*0.4);
				}
				if(defined $ftem_snp){
					my ($oligo_snp)=&get_oligo($id, $p, $l, $seq_snp{$id}, $pori);
					print P $id_new,"\t",$oligo,":", $oligo_snp, "\n";
					print PT $id_new,"\t",$oligo,":", $oligo_snp, "\n";
				}else{
					print P $id_new,"\t",$oligo,"\n";
					print PT $id_new,"\t",$oligo,"\n";
				}
				$seq{$id_new}=$oligo;
				last; ##  oligos of different length are evalued in oligo_evaluation.pl
			}
			close(P);
		}
	}
}
close(PT);

# evalue
my @foligo = glob("$outdir/split_*/$fkey.oligo.list*");
open (SH, ">$outdir/$fkey.oligo.evalue.sh") or die $!;
foreach my $f (@foligo){	
	my $fname = basename($f);
	my $dir_new = dirname($f);
	my $olens=join(",", $min_len, $max_len, $scale_len); 
	my $cmd = "perl $Bin/oligo_evaluation.pl --nohead -p $f -d $fdatabases -thread 1 -stm $stm -k $fname -opttm $opt_tm -olen $olens -od $dir_new";
	if($orient eq "FR"){
		$cmd .= " --Revcom";
	}
	if(defined $probe){
		$cmd .= " --Probe -opttmp $opt_tm_probe";
	}
	if(defined $NoSpecificity){
		$cmd .= " --NoSpecificity";
	}
	if(defined $NoFilter){
		$cmd .= " --NoFilter";
	}
	$cmd .= " >$dir_new/$fname.log 2>&1";
	print SH $cmd,"\n";
}
close (SH);
Run("parallel -j $para_num  < $outdir/$fkey.oligo.evalue.sh", 1);

##cat
my @dirs = glob("$outdir/split_*");
foreach my $dir (@dirs){
	Run("cat $dir/*.evaluation.out > $dir/evaluation.out", 1);
	Run("cat $dir/*.bound.info > $dir/bound.info", 1);
	Run("cat $dir/*.filter.list > $dir/filter.list", 1);
}
Run("cat $outdir/*/evaluation.out >$outdir/$fkey.oligo.evaluation.out", 1);
Run("cat $outdir/*/bound.info >$outdir/$fkey.oligo.bound.info", 1);
Run("cat $outdir/*/filter.list >$outdir/$fkey.oligo.filter.list", 1);




#######################################################################################
print STDOUT "\nDone. Total elapsed time : ",time()-$BEGIN_TIME,"s\n";
#######################################################################################

# ------------------------------------------------------------------
# sub function
# ------------------------------------------------------------------

#dfnum: files num in one dir
#flnum: lines num in one file
#rnum: rank num of dir
sub split_file{
	my ($file, $odir, $flnum, $dfnum)=@_;
	my $total = `wc -l $file`;
	($total) = split /\s+/, $total;
	my $fname = basename($file);
	my $dlnum = $dfnum*$flnum;
	my @sfile;
	my $rnum;
	if($total/$dlnum < 1){ ## one rank
		Run("split -l $flnum $file $odir/$fname\_");
		@sfile = glob("$odir/$fname\_*");
		$rnum = 1;
	}else{ ## two rank
		Run("split -l $dlnum $file $odir/$fname\_");
		@sfile = glob("$odir/$fname\_*");
		foreach my $f (@sfile){
			my ($nid) = $f=~/$fname\_(\S+)/;
			my $dir_new = "$odir/dir_$nid";
			mkdir $dir_new unless(-d $dir_new);
			Run("split -l $flnum $f $dir_new/$fname\_$nid\_");
		}
		@sfile = glob("$odir/dir_*/$fname\_*");
		$rnum = 2;
	}
	return ($rnum, @sfile);
}



sub get_oligo{
	my ($id, $pos, $len, $seq, $ori)=@_;
	my $oligo;
	my ($start, $end);
	if($ori eq "F"){
		$oligo = substr($seq, $pos-$len, $len);
		$start=$pos-$len+1;
		$end=$pos;
	}else{
		$oligo = substr($seq, $pos, $len);
		$oligo=&revcom($oligo);
		$start=$pos+1;
		$end=$pos+$len;
	}
	if(length $oligo < $len){
		print "Extract oligo failed! $seq, $pos, $len, $ori\n";
		die;
	}
	return ($oligo, $start, $end);
}

sub check_merge_rregion{
	my ($rregion)=$_;
	##check regions
	my @rregion = split /,/, $regions;
	my $nrregion = scalar @rregion;
	if($nrregion!=3 && $nrregion!=6){
		print "Wrong: number of -rregion must be 3 or 6!\n";
		die;
	}
	for(my $i=0; $i<@rregion; $i+=3){
		if($rregion[$i+1]-$rregion[$i] < 0){
			print "Wrong: -rregion region must be ascending ordered, eg:3,40,1,100,150,5\n";
			die;
		}
	}

	if($nrregion==3){
		return(@rregion);
	}else{ ##merge when overlap
		my ($s1, $e1, $b1, $s2, $e2, $b2) = @rregion;
		## sort two regions
		if($s1 > $s2){
			($s2, $e2, $b2) = @rregion[0..2];
			($s1, $e1, $b1) = @rregion[3..5];
		}
		if($e1>=$s2){ ## overlap
			if($e1>$e2){ ## r1 include r2
				if($b1<$b2){ ## prefer min bin
					return($s1, $e1, $b1);
				}else{
					return ($s1, $s2, $b1, $s2+1, $e2, $b2, $e2+1, $e1, $b1);
				}
			}else{## intersect 
				if($b1<$b2){
					return ($s1, $e1, $b1, $e1+1, $e2, $b2);
				}else{
					return ($s1, $s2, $b1, $s2+1, $e2, $b2);
				}
			}
		}else{## no overlap
			return @rregion;
		}

	}
}


sub Run{
    my ($cmd, $nodie)=@_;

    my $ret = system($cmd);
    if (!$nodie && $ret) {
        die "Run $cmd failed!\n";
    }
}



sub USAGE {#
	my $usage=<<"USAGE";
Program:
Version: $version
Contact:zeng huaping<huaping.zeng\@genetalks.com> 

Usage:
  Options:
  -i  	<file>   	Input template fa file, forced
  -is  	<file>   	Input template add snp fa file, optional
  -d    <files>     Input database files separated by ",", [$fdatabases]
  -fr   <F|R|FR>	oligo orient on template, F: forward, R: reverse, FR: both forward and reverse, forced
  -k  	<str>		Key of output file, forced

  --Probe                design probe
  --NoSpecificity   not evalue specificity
  --FilterRepeat	filter oligos with repeat region(lowercase in fdatabases) more than 40%
  --NoFilter             Not filter any oligos

  -ptype     <str>       oligo type, "face-to-face", "back-to-back", "Nested", [$ptype]
  -opttm    <int>       optimal tm, [$opt_tm]
  -opttmp   <int>       optimal tm of probe, [$opt_tm_probe]
  -rlen     <str>       oligo len ranges(start,end,scale), start <= end, [$range_len]
  -rregion     <str>       region ranges(start,end,scale), start <= end, separated by ",", (1,len,1) when not given, optional
  		                Example: 
			               sanger sequence oligo: 100,150,2,400,500,5
			               ARMS PCR oligo: 1,1,1,80,180,2
  -stm     <int>	min tm to be High_tm in specifity, [$stm]
  -para    <int>	parallel num, [$para_num]
  -od <dir>	Dir of output file, default ./
  -h		 Help

USAGE
	print $usage;
	exit;
}
