#!/usr/bin/perl
#
# Copyleft O. Sotolongo-Grau (osotolongo@fundacioace.org)
#
# Script para convertir los fastq en CRAM
#
use strict;
use warnings;
use SLURMACE qw(send2slurm);
use File::Find::Rule;
use Cwd;
use File::Temp qw( :mktemp tempdir);
use FindBin; 
use lib "$FindBin::Bin";
use wxsInit;
my $cfile;
my $outdir;
my $workdir = getcwd;
my $debug = 0;
my $init;
my $tmpdir =  $ENV{TMPDIR};
############################################################
# Variables con los PATHS. Cambiar aqui lo que sea necesario
#############################################################
my %dpaths = data_paths();
my $tmp_shit = $ENV{TMPDIR};
my $ref_fa = $dpaths{ref_dir}.'/'.$dpaths{ref_name}.'.fasta';
#################################################################
#################################################################
#################################################################
my %epaths = exec_paths();

@ARGV = ("-h") unless @ARGV;
while (@ARGV and $ARGV[0] =~ /^-/) {
	$_ = shift;
	last if /^--$/;
	if (/^-c/) { $cfile = shift; chomp($cfile);}
	if (/^-g/) { $debug = 1;}
	if (/^-i/) { $init = shift; chomp($init);}
}
die "Should supply init data file\n" unless $init;
my %wesconf = init_conf($init);
$wesconf{outdir} = $workdir.'/output' unless $wesconf{outdir};
mkdir $wesconf{outdir} unless -d $wesconf{outdir};
my $slurmdir = $wesconf{outdir}.'/slurm';
mkdir $slurmdir unless -d $slurmdir;

my %ptask = (cpus => 8, job_name => 'wes', time => '8:0:0', mem_per_cpu => '4G', debug => $debug);

die "No such directory mate\n" unless -d $wesconf{src_dir};
my @content = find(file => 'name' => "*$wesconf{search_pattern}", in => $wesconf{src_dir});
my %pollos = map {/.*\/(\w+?)$wesconf{search_pattern}$/; $1 => $_} @content;
my @cuts;
if ($cfile) {
	open IDF, "<$cfile" or die "No such input file!\n";
	@cuts = <IDF>;
	chomp @cuts;
	close IDF;
}


foreach my $shit (sort keys %pollos){
	my $go = 0;
	if ($cfile) {
		if (grep {/$shit/} @cuts) {$go = 1;}
	}else{
		$go = 1;
	}
	if (-f $pollos{$shit} and $go) {
		$ptask{job_name} = 'compact_data';
		$ptask{filename} = $slurmdir.'/'.$shit.'.sh';
		$ptask{output} = $slurmdir.'/'.$shit.'.out';
		(my $another = $pollos{$shit}) =~ s/$wesconf{search_pattern}/$wesconf{alt_pattern}/;
		my $rg = '"@RG\\tID:'.$shit.'\\tPL:'.$wesconf{platform}.'\\tLB:'.$wesconf{libraries}.'\\tSM:'.$shit.'"';
		$ptask{command} = $epaths{bwa}.' -R '.$rg.' '.$ref_fa.' '.$pollos{$shit}.' '.$another.' | '.$epaths{gatk}.' SortSam -I /dev/stdin -O '.$tmpdir.'/'.$shit.'_sorted.bam --SORT_ORDER coordinate --CREATE_INDEX true'." --TMP_DIR $tmp_shit\n";
		$ptask{command}.= $epaths{samtools}.' view -@ 8 -T '.$ref_fa.' -C -o '.$wesconf{outdir}.'/'.$shit.'.cram '.$tmpdir.'/'.$shit.'_sorted.bam'."\n";
		$ptask{command}.= 'rm '.$tmpdir.'/'.$shit.'_sorted.bam';
		send2slurm(\%ptask);
	}
}

unless ($debug) {
	my %warn = (filename => $slurmdir.'/compact_end.sh', output => $slurmdir.'/compact_end.out', job_name => 'compact_data', mailtype => 'END', dependency => 'singleton');
	send2slurm(\%warn);
}
