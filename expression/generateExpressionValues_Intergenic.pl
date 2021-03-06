#!/usr/bin/perl -w
#Written by Malachi Griffith
#Copyright 2009 Malachi Griffith
#This file is part of 'ALEXA-Seq'
#ALEXA-Seq is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#ALEXA-Seq is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#You should have received a copy of the GNU General Public License along with ALEXA-Seq (COPYING.txt).  If not, see <http://www.gnu.org/licenses/>.

#The purpose of this script is to generate intergenic level expression values for the non-genic content of the genome
#Intergenics are summarized at three levels (each utilizing only the non-masked bases): (a) entire intergenics; (b) 'silent' intergenic regions (c) 'active' intergenic regions
#- Silent and active regions here were previously annotated by incorporating EST and mRNA data
#The input is a tabular file summarizing the top hits of WTSS read pairs to a database of all intergenic regions
#The user also inputs previously annotated Intergenic, Active Region and Silent Region database files
#The outputs are intergenic and active/silent intergenic region expression value files (one line per intergenic or active/silent region)

#UCSC wiggle tracks summarizing base level expression for all intergenics are also created
#UCSC GFF tracks are also created to display annotated intergenics and active/silent intergenic regions within them.

#Each INTERGENIC  will be assigned values as follows:
#Raw_Read_Count - number of unambiguous reads meeting a bit score cutoff
#Norm_Read_Count - read count normalized to a user specified library size (use the # of quality, unambiguously mapped reads for the smaller library)
#Average_Base_Coverage - Total base coverage divided by number of unmasked bases in the intergenic
#Norm1_Average_Base_Coverge - Normalized to user specified library size (use the # of quality, unambiguously mapped reads for the smaller library)

#Each ACTIVE/SILENT intergenic region will be assigned values as follows:
#Average_Base_Coverage - Total base coverage divided by number of unmasked bases in the intergenic
#Norm1_Average_Base_Coverge - Normalized to user specified library size (use the # of quality, unambiguously mapped reads for the smaller library)
 
#STEPS
#1.) For the user specified chromosome, get all reads out of the input mapped reads file
#    - Store a Berkley DB file in a working dir (or as a flat file)

#2.) Import the intergenic and ACTIVE/SILENT intergenic regions annotation files

#3.) Get basic gene info from ALEXA (genes, exon content coords, etc.)
#    - Foreach gene, get the upstream and downstream intergenic region
#    - Make note of the Active Intergenic regions from these Intergenic regions that are within some arbitrary distance (say 100k from the beginning or end of each gene)
#    - For each gene summarize (IG = InterGenicRegion, AIG = ActiveInterGenicRegion, SIG = SilentInterGenicRegion):
#    - IG_Count, AIG_Count, AIG_Base_Count, Observed_AIG_Count

#4.) Build a base-by-base coverage object for each INTERGENIC (store in memory or as a Berkley DB)

#    - INTERGENIC coverage object
#    - Use a intergenic_position key as follows: key{'IntergenicID_ChromosomePosition'} value{read_base_coverage}

#5.) Correct base count values at the INTERGENIC level
#    - correct base counts to account for library size (normalize to a user specified library size - use the number of mapped reads in the smaller library)
#    - correct base counts to account for mapability

#6.) Summarize intergenic and ACTIVE/SILENT intergenic region expression values.  

#7.) Generate a UCSC wig file for the entire chromosome region being processed
#    - Use the library size corrected base coverage values
#    - Also create annotation tracks for all intergenics, active intergenic regions and silent intergenic regions


use strict;
use Data::Dumper;
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use File::Basename;
use BerkeleyDB;

#Load the ALEXA modules
BEGIN {
  use Cwd 'abs_path';
  if (abs_path($0) =~ /(.*)\/.*\/.*\.pl/){
    push (@INC, $1);
  }
}
use utilities::ALEXA_DB qw(:all);
use utilities::utility qw(:all);
use utilities::mapping qw(:all);

my $database = '';
my $server = '';
my $user = '';
my $password = '';
my $library = '';
my $library_name = '';
my $chr_filter = '';
my $read_record_dir = '';
my $mapped_reads_dir = '';
my $annotation_dir = '';
my $min_bit_score = ''; 
my $min_seq_coverage = '';
my $working_dir = '';
my $results_dir = '';
my $ucsc_dir = '';
my $ucsc_build = '';
my $web_path = '';
my $color_set = '';
my $cutoffs_file = '';
my $log_file = '';

GetOptions ('database=s'=>\$database,'server=s'=>\$server, 'user=s'=>\$user, 'password=s'=>\$password,
	    'library=s'=>\$library, 'library_name=s'=>\$library_name, 'ucsc_build=s'=>\$ucsc_build,
	    'chr_filter=s'=>\$chr_filter, 'read_record_dir=s'=>\$read_record_dir, 'mapped_reads_dir=s'=>\$mapped_reads_dir, 'annotation_dir=s'=>\$annotation_dir,
            'min_bit_score=f'=>\$min_bit_score, 'min_seq_coverage=f'=>\$min_seq_coverage, 'working_dir=s'=>\$working_dir, 'results_dir=s'=>\$results_dir, 
            'ucsc_dir=s'=>\$ucsc_dir, 'web_path=s'=>\$web_path, 'color_set=i'=>\$color_set, 'cutoffs_file=s'=>\$cutoffs_file, 'log_file=s'=>\$log_file);

#Provide instruction to the user
print GREEN, "\n\nUsage:", RESET;
print GREEN, "\n\tThis script builds a Berkley DB (one file per chromosome) and stores a record for every intergenic base position", RESET;
print GREEN, "\n\tSpecify the ALEXA database and server to query using: --database and --server", RESET;
print GREEN, "\n\tSpecify the ALEXA user and password for access using: --user and --password", RESET;
print GREEN, "\n\tSpecify the library ID for read data using: --library", RESET;
print GREEN, "\n\tSpecify the library name for read data using: --library_name", RESET;
print GREEN, "\n\tSpecify the chromosome (sub-range) to be processed using: --chr_filter", RESET;
print GREEN, "\n\tSpecify a directory containing files of reads mapped to INTERGENIC REGIONS using: --mapped_reads_dir", RESET;
print GREEN, "\n\tSpecify a directory containing read record files for this library using:  --read_record_dir", RESET;
print GREEN, "\n\t\tThis directory should contain all of the lanes for a single library only - and the files must be compressed", RESET;
print GREEN, "\n\tSpecify the directory containing annotatation files using: --annotation_dir", RESET;
print GREEN, "\n\tSpecify the minimum bit score to a transcript for each read to be considered for the summary using: --min_bit_score", RESET;
print GREEN, "\n\tSpecify the minimum percent sequence coverage for an observed sequence to be considered expressed and written to the UCSC custom track using: --min_seq_coverage", RESET;
print GREEN, "\n\tSpecify the working directory to write binary tree files to using: --working_dir", RESET;
print GREEN, "\n\tSpecify the a directory to write final GENE/INTERGENIC results files to using: --results_dir", RESET;
print GREEN, "\n\tSpecify the target UCSC directory for custom UCSC track files using: --ucsc_dir", RESET;
print GREEN, "\n\tSpecify the UCSC build to be used for links to UCSC tracks using: --ucsc_build (e.g. hg18)", RESET;
print GREEN, "\n\tSpecify the html web path to this directory using: --web_path", RESET;
print GREEN, "\n\tSpecify which hard coded color set to use using: --color_set (1 for LibraryA, 2 for LibraryB)", RESET;
print GREEN, "\n\tSpecify the path to a file containing expression cutoffs values using:  --cutoffs_file", RESET;
print GREEN, "\n\t\tIf these have not been calculated yet, use: --cutoffs=0", RESET;
print GREEN, "\n\tSpecify a log file using: --log_file", RESET;

print GREEN, "\n\nExample: generateExpressionValues_Intergenic.pl  --database=ALEXA_hs_49_36k  --server=jango.bcgsc.ca  --user=viewer  --password=viewer  --library=HS04391  --library_name=MIP101  --chr_filter='3:10:118167002-127874001'  --working_dir=/projects/malachig/solexa/read_records/HS04391/Intergenics_v49/Summary/temp/  --min_bit_score=60.0  --min_seq_coverage=75.0  --mapped_reads_dir=/projects/malachig/solexa/read_records/HS04391/Intergenics_v49/  --read_record_dir=/projects/malachig/solexa/read_records/HS04391/  --annotation_dir=/projects/malachig/sequence_databases/hs_49_36k/intergenics/   --results_dir=/projects/malachig/solexa/read_records/HS04391/Intergenics_v49/Summary/intergenic_results/  --ucsc_dir=/home/malachig/www/public/htdocs/solexa/HS04391/  --web_path=http://www.bcgsc.ca/people/malachig/htdocs/solexa/HS04391/  --color_set=1  --cutoffs_file=/projects/malachig/solexa/figures_and_stats/HS04391/Expression_v49/HS04391_NORM1_average_coverage_cutoffs.txt  --log_file=/projects/malachig/solexa/logs/HS04391/generateExpressionValues/Intergenic/generateExpressionValues_Intergenic_chr3_10.txt\n\n", RESET;

unless ($database && $server && $user && $password && $library && $library_name && $chr_filter && $annotation_dir && $mapped_reads_dir && $read_record_dir && $min_bit_score && $min_seq_coverage && $working_dir && $results_dir && $ucsc_dir && $ucsc_build && $web_path && $color_set && ($cutoffs_file || $cutoffs_file eq '0') && $log_file){
  print RED, "\nRequired input parameter(s) missing\n\n", RESET;
  exit();
}

#Scale all expression values to a constant value (values will be scaled to what they would be expected to be if the library contained 10 billion mapped bases)
#If a library has less than this, the normalized expression values will be increased and vice versa
#The actual number of mapped bases is determined by parsing the 'read record' files and counting ALL bases that have been unambiguously assigned to one of the following classes:
#'ENST_U', 'INTRON_U', 'INTERGENIC_U', 'NOVEL_JUNCTION_U', 'NOVEL_BOUNDARY_U' 
my $library_normalization_value = 10000000000;
my $library_size;

#Set priority values to determine ordering of custom tracks
my $priority_annotation = 20;
my $priority_expression = 50;
my $priority_wiggle = 70;

#Define some color profiles - '1' for one library, '2' for the second library 
my %colors;
$colors{'1'}{0} = "153,0,0";      #Brick Red     - All annotation tracks
$colors{'1'}{1} = "153,51,0";     #Red-Brown
$colors{'1'}{2} = "51,204,102";   #Dark Teal     - All intergenic expression tracks for library '1'

$colors{'2'}{0} = "153,0,0";      #Brick Red     - All annotation tracks
$colors{'2'}{1} = "153,51,0";     #Red-Brown
$colors{'2'}{2} = "102,255,153";  #Light Teal    - All intergenic expression tracks for library '2'

unless ($colors{$color_set}){
  print RED, "\nColor set specified by user is not understood", RESET;
  print Dumper %colors;
  exit();
}

my $file_name_prefix;
my $region_number;
my $start_filter;
my $end_filter;
if ($chr_filter =~ /(.*)\:(\d+)\:(\d+)\-(\d+)/){
  $chr_filter = $1;
  $region_number = $2;
  $start_filter = $3;
  $end_filter = $4;
  $file_name_prefix = "$chr_filter"."_"."$region_number";
  unless ($end_filter > $start_filter){
    print RED, "\nStart of range must be smaller than end ($chr_filter)\n\n", RESET;
    exit();
  }
}else{
  print RED, "\nFormat of chr_filter not understood: $chr_filter (should be of the form:  Y:1:1-9999001)\n\n", RESET;
  exit();
}

if ($chr_filter eq "MT"){$chr_filter = "M"};

#Check working dirs before proceeding
#Multiple scripts may be writing to the directory, do not clear
#All files will be names chrN______
$mapped_reads_dir = &checkDir('-dir'=>$mapped_reads_dir, '-clear'=>"no");
$read_record_dir = &checkDir('-dir'=>$read_record_dir, '-clear'=>"no");
$working_dir = &checkDir('-dir'=>$working_dir, '-clear'=>"no");
$ucsc_dir = &checkDir('-dir'=>$ucsc_dir, '-clear'=>"no");
$results_dir = &checkDir('-dir'=>$results_dir, '-clear'=>"no");
$annotation_dir = &checkDir('-dir'=>$annotation_dir, '-clear'=>"no");

open (LOG, ">$log_file") || die "\nCould not open log file: $log_file\n\n";


#Open global Berkley DB files for reading or writing
my %chr_reads;
my %intergenic_coverage;
my %intergenic_coverage_norm1;
my %chr_coverage;
my %chr_coverage_norm1;
my %ensembl_intergenic_tracks;
my %ensembl_active_region_tracks;
my %ensembl_silent_region_tracks;

my $berk = 0;
my $rm_cmd = "rm -f $working_dir"."*chr"."$file_name_prefix"."_"."*";
if ($berk == 1){
  #Delete pre-existing berkley DB files for the current chromosome
  print YELLOW, "\nDeleting Berkley DB files and creating new\n\t($rm_cmd)\n\n", RESET;
  print LOG "\nDeleting Berkley DB files and creating new\n\t($rm_cmd)\n\n";
  system($rm_cmd);

  my $chr_reads_file = "$working_dir"."chr"."$file_name_prefix"."_MappedReads.btree";
  tie(%chr_reads, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_reads_file , -Flags => DB_CREATE) or die "can't open file $chr_reads_file: $! $BerkeleyDB::Error\n";

  my $intergenic_coverage_file = "$working_dir"."chr"."$file_name_prefix"."_IntergenicCoverage.btree";
  tie(%intergenic_coverage, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $intergenic_coverage_file, -Flags => DB_CREATE) or die "can't open file $intergenic_coverage_file: $! $BerkeleyDB::Error\n";

  my $intergenic_coverage_norm1_file = "$working_dir"."chr"."$file_name_prefix"."_IntergenicCoverage_norm1.btree";
  tie(%intergenic_coverage_norm1, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $intergenic_coverage_norm1_file, -Flags => DB_CREATE) or die "can't open file $intergenic_coverage_norm1_file: $! $BerkeleyDB::Error\n";

  my $chr_coverage_file = "$working_dir"."chr"."$file_name_prefix"."_ChrCoverage.btree";
  tie(%chr_coverage, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_coverage_file, -Flags => DB_CREATE) or die "can't open file $chr_coverage_file: $! $BerkeleyDB::Error\n";

  my $chr_coverage_norm1_file = "$working_dir"."chr"."$file_name_prefix"."_ChrCoverage_norm1.btree";
  tie(%chr_coverage_norm1, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_coverage_norm1_file, -Flags => DB_CREATE) or die "can't open file $chr_coverage_norm1_file: $! $BerkeleyDB::Error\n";

  my $chr_intergenic_file = "$working_dir"."chr"."$file_name_prefix"."_IntergenicAnnotations.btree";
  tie(%ensembl_intergenic_tracks, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_intergenic_file, -Flags => DB_CREATE) or die "can't open file $chr_intergenic_file: $! $BerkeleyDB::Error\n";

  my $chr_active_region_file = "$working_dir"."chr"."$file_name_prefix"."_ActiveRegions.btree";
  tie(%ensembl_active_region_tracks, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_active_region_file, -Flags => DB_CREATE) or die "can't open file $chr_active_region_file: $! $BerkeleyDB::Error\n";

  my $chr_silent_region_file = "$working_dir"."chr"."$file_name_prefix"."_SilentRegions.btree";
  tie(%ensembl_silent_region_tracks, 'BerkeleyDB::Btree', -Cachesize => 256000000, -Filename=> $chr_silent_region_file, -Flags => DB_CREATE) or die "can't open file $chr_silent_region_file: $! $BerkeleyDB::Error\n";
}

#0.) If specified, get the gene-by-gene expression cutoffs.
#    - These will be used to decide whether a particular sequence is expressed or not
my $gene_cutoffs_ref;
if ($cutoffs_file && -e $cutoffs_file){
  $gene_cutoffs_ref = &importExpressionCutoffs ('-cutoffs_file'=>$cutoffs_file);
}else{
  $cutoffs_file = 0;
  print YELLOW, "\nCutoffs file not specified - or not found, expression will be evaluated by percent coverage only\n\n", RESET;
}


#1-A.) For the user specified chromosome, get all reads out of the input mapped reads file
#    - Store a Berkley DB file in a working dir (or as a flat file)
my $grand_total_mapped_reads = 0;  #Count all the quality unambiguous mapped reads from ANY chromosome
&parseMappedReads('-indir'=>$mapped_reads_dir, '-chromosome'=>$chr_filter, '-range'=>"$start_filter-$end_filter", '-min_bit_score'=>$min_bit_score, '-working_dir'=>$working_dir);

#1-B.) Go through the read records files and remove reads from those stored if they have not been assigned to the correct class
my $read_class = "INTERGENIC_U";
$library_size = &importLibrarySize ('-read_records_dir'=>$read_record_dir);


#2.) Import the intergenic and silent/active region annotation files 
my $intergenics_ref;
my $active_regions_ref;
my $silent_regions_ref;
my $intergenic_header;
my $active_header;
my $silent_header;
&importIntergenicAnnotations('-input_dir'=>$annotation_dir, '-chromosome'=>$chr_filter, '-range'=>"$start_filter-$end_filter");


#3.) Get basic gene info from ALEXA (genes, exon content coords, etc.)
my $genes_ref;
&getBasicGeneInfo('-chromosome'=>$chr_filter, '-range'=>"$start_filter-$end_filter");

#4.) Build a base-by-base coverage object for each INTERGENIC REGION (store in memory or as a Berkley DB)
#    - At the same time, Build a base-by-base coverage object for the entire CHROMOSOME
&buildCoverageObjects('-chromosome'=>$chr_filter, '-range'=>"$start_filter-$end_filter", '-working_dir'=>$working_dir);


#5.) Correct base count values at the INTERGENIC level
#    - correct base counts to account for library size (normalize to a user specified library size - use the number of mapped reads in the smaller library)
&correctBaseCounts('-normalization_value'=>$library_normalization_value, '-library_size'=>$library_size);


#6.) Summarize intergenic expression values
&printSummary('-results_dir'=>$results_dir);


#7.) Generate a UCSC wig file for the entire chromosome region being processed
#    - Use the library size and mapability corrected base coverage values
&printUCSCTrack('-ucsc_dir'=>$ucsc_dir, '-chr'=>$chr_filter, '-library'=>$library);

#If neccessary, clean berkeley DB files
if ($berk == 1){
  #Cleanly untie the berkley dbs
  untie (%chr_coverage);
  untie (%chr_coverage_norm1);
  untie (%intergenic_coverage);
  untie (%intergenic_coverage_norm1);
  untie (%ensembl_intergenic_tracks);
  untie (%ensembl_active_region_tracks);
  untie (%ensembl_silent_region_tracks);
  untie (%chr_reads);
  #Delete temp berkley DB files created by this script in the working dir (for the target chromosome)
  print YELLOW, "\n\nScript complete, deleting Berkley DB files\n\t($rm_cmd)\n\n", RESET;
  print LOG "\n\nScript complete, deleting Berkley DB files\n\t($rm_cmd)\n\n";
  system($rm_cmd);
}

#Summarize the total memory usage at close (since Perl doesnt usually release memory ... this should be the max used by the script):
my $pid = $$;
my $ps_query = `ps -p $pid -o pmem,rss`;
my @process_info = split ("\n", $ps_query);
my $memory_usage = '';
my $memory_usage_p = '';
if ($process_info[1] =~ /(\S+)\s+(\S+)/){
  $memory_usage_p = $1;
  $memory_usage = $2;
}
my $memory_usage_m = sprintf("%.1f", ($memory_usage/1024));
print YELLOW, "\n\nMemory usage at end of script: $memory_usage_m Mb ($memory_usage_p%)", RESET; 
print LOG "\n\nMemory usage at end of script: $memory_usage_m Mb ($memory_usage_p%)"; 

print "\n\nSCRIPT COMPLETE\n\n";
print LOG "\n\nSCRIPT COMPLETE\n\n";

close(LOG);

exit();


################################################################################################################################################
#For the user specified chromosome, get all reads out of the input mapped reads file (above a certain quality) and store seperately
################################################################################################################################################
sub parseMappedReads{
  my %args = @_;
  my $indir = $args{'-indir'};
  my $target_chr = $args{'-chromosome'};
  my $range = $args{'-range'};
  my $min_bit_score = $args{'-min_bit_score'};
  my $working_dir = $args{'-working_dir'};

  $target_chr = "chr"."$target_chr";

  my $start_filter;
  my $end_filter;
  if ($range =~ /(\d+)\-(\d+)/){
    $start_filter = $1;
    $end_filter = $2;
  }else{
    print RED, "\nProblem with range - parseMappedReads()\n\n", RESET;
    exit();
  } 

  print BLUE, "\n1.) Begin parsing input files for target chr ($target_chr) reads: $indir", RESET;
  print LOG "\n1.) Begin parsing input files for target chr ($target_chr) reads: $indir";

  my %columns;
  my @required_columns = qw(Read_ID DistanceBetweenReads R1_ID R1_HitType R1_IntergenicName R1_Strand R1_AlignmentLength R1_PercentIdentity R1_BitScore R1_ChrStart R1_ChrEnd R2_ID R2_HitType R2_IntergenicName R2_Strand R2_AlignmentLength R2_PercentIdentity R2_BitScore R2_ChrStart R2_ChrEnd);

  my $passing_reads = 0;

  #Get files from this directory
  print BLUE, "\n\nSearching $indir for mapped read files", RESET;
  print LOG "\n\nSearching $indir for mapped read files";

  my %mapped_read_files;
  opendir(DIRHANDLE, "$indir") || die "\nCannot open directory: $indir\n\n";
  my @test_files = readdir(DIRHANDLE);
  my $file_count = 0;

  foreach my $test_file (sort @test_files){
    my $file_path = "$indir"."$test_file";

    #Skip directories within the specified directory
    if (-e $file_path && -d $file_path){
      print YELLOW, "\n\t$file_path  is a directory - skipping", RESET;
      print LOG "\n\t$file_path  is a directory - skipping";
      next();
    }

    #If the results file is compressed uncompress it
    unless ($file_path =~ /(.*)\.gz$/){
      print RED, "\nFound an uncompressed file: $file_path\n\n\tMake sure all files are compressed before proceeding\n\n\t- A mix of compressed and uncompressed files may indicate a problem (i.e. you need to figure out which is complete and which might be partial!!)\n\n", RESET;
      exit();
    }

    $file_count++;
    print BLUE, "\n\t$file_path was added to the list of files to be processed", RESET;
    print LOG "\n\t$file_path was added to the list of files to be processed";

    $mapped_read_files{$file_count}{path} = $file_path;
  }

  my $num_files = keys %mapped_read_files;
  print BLUE, "\n\nBegin parsing $num_files mapped read files", RESET;
  print LOG "\n\nBegin parsing $num_files mapped read files";

  foreach my $file_count (sort {$mapped_read_files{$a}{path} cmp $mapped_read_files{$b}{path}} keys %mapped_read_files){
    my $infile = $mapped_read_files{$file_count}{path};
    print BLUE, "\n\nProcessing file: $infile", RESET;
    print LOG "\n\nProcessing file: $infile";

    my $line_counter = 0;
    my $block_count = 0;
    my $block_size = 100000;
    my $header_line = 1;
    my $header;

    open (READ, "zcat $infile |") || die "\nCould not open read records summary infile: $infile\n\n";
    while(<READ>){
      $line_counter++;

      if ($line_counter == $block_size){
        $block_count++;

        $| = 1; print BLUE, "\n\tBlock $block_count (of size $block_size).  Found $passing_reads unambigous reads (cumulative) matching the target chromosome $target_chr:$range (bit score >= $min_bit_score)", RESET; $| = 0;
        print LOG "\n\tBlock $block_count (of size $block_size).  Found $passing_reads unambigous reads (cumulative) matching the target chromosome $target_chr:$range (bit score >= $min_bit_score)";

        $line_counter = 0;
      }

      chomp($_);
      my $current_line = $_;
      my @line = split("\t", $_);

      #Parse the column names and positions.  Check against a hard coded list of required columns before proceeding
      if ($header_line == 1){
        $header = $current_line;
        my $col_count = 0;
        foreach my $column (@line){
	  $columns{$column}{position} = $col_count;
	  $col_count++;
        }

        foreach my $req_column (@required_columns){
	  unless ($columns{$req_column}){
	    print RED, "\nRequired column: $req_column was not found in the read record file!\n\n", RESET;
	    exit();
	  }
        }
        $header_line = 0;
        next();
      }

      my $r1_id = $line[$columns{R1_ID}{position}];
      my $r2_id = $line[$columns{R2_ID}{position}];
      my $r1_intergenic_id = $line[$columns{R1_IntergenicName}{position}];
      my $r2_intergenic_id = $line[$columns{R2_IntergenicName}{position}];
      my $r1_hit_type = $line[$columns{R1_HitType}{position}];
      my $r2_hit_type = $line[$columns{R2_HitType}{position}];
      my $r1_bit_score = $line[$columns{R1_BitScore}{position}];
      my $r2_bit_score = $line[$columns{R2_BitScore}{position}];
      my $r1_chr = $line[$columns{R1_Chr}{position}];
      my $r2_chr = $line[$columns{R2_Chr}{position}];
      my $r1_chr_start = $line[$columns{R1_ChrStart}{position}];
      my $r2_chr_start = $line[$columns{R2_ChrStart}{position}];
      my $r1_chr_end = $line[$columns{R1_ChrEnd}{position}];
      my $r2_chr_end = $line[$columns{R2_ChrEnd}{position}];

      #Check for uninitialized values
      unless ($r1_id && $r2_id && $r1_intergenic_id && $r2_intergenic_id && $r1_hit_type && $r2_hit_type && $r1_chr && $r2_chr){
        print RED, "\nFound uninitialized values in mapped reads input file: $infile - aborting", RESET;
        exit();
      }

      #Count quality, unambiguous mapped reads to ANY chromosome
      if (($r1_hit_type eq "Top_Hit") && ($r1_bit_score >= $min_bit_score)){
        $grand_total_mapped_reads++;
      }
      if (($r2_hit_type eq "Top_Hit") && ($r2_bit_score >= $min_bit_score)){
        $grand_total_mapped_reads++;
      }

      #Deal with Read 1
      unless ($r1_intergenic_id eq "NA"){
        my $r1_chromosome = "chr"."$r1_chr";

        #Fix chromosome formats
        if ($r1_chromosome eq "chrMT"){$r1_chromosome = "chrM";}

        if (($r1_hit_type eq "Top_Hit") && ($r1_bit_score >= $min_bit_score) && ($r1_chromosome eq "$target_chr")){

          if ($r1_chr_start >= $start_filter && $r1_chr_start <= $end_filter && $r1_chr_end >= $start_filter && $r1_chr_end <= $end_filter){
            $passing_reads++;
            my $string = "$r1_intergenic_id\t$r1_chr_start\t$r1_chr_end";
            $chr_reads{$r1_id} = $string;
          }
        }
      }

      #Deal with Read 2
      unless ($r2_intergenic_id eq "NA"){
        my $r2_chromosome = "chr"."$r2_chr";

        #Fix chromosome formats
        if ($r2_chromosome eq "chrMT"){$r2_chromosome = "chrM";}

        if (($r2_hit_type eq "Top_Hit") && ($r2_bit_score >= $min_bit_score) && ($r2_chromosome eq "$target_chr")){

          if ($r2_chr_start >= $start_filter && $r2_chr_start <= $end_filter && $r2_chr_end >= $start_filter && $r2_chr_end <= $end_filter){
            $passing_reads++;
            my $string = "$r2_intergenic_id\t$r2_chr_start\t$r2_chr_end";
            $chr_reads{$r2_id} = $string;
          }
        }
      }
    }
  }

  $| = 1; print BLUE, "\n\n\tFound a total of $passing_reads unambigous reads matching the target chromosome (bit score >= $min_bit_score)", RESET; $| = 0;
  $| = 1; print BLUE, "\n\tFound a grand total of $grand_total_mapped_reads unambigous reads matching ANY chromosome (bit score >= $min_bit_score)", RESET; $| = 0;
  print LOG "\n\n\tFound a total of $passing_reads unambigous reads matching the target chromosome (bit score >= $min_bit_score)";
  print LOG "\n\tFound a grand total of $grand_total_mapped_reads unambigous reads matching ANY chromosome (bit score >= $min_bit_score)";

  return();
}


############################################################################################################################################
#Import the intergenic annotations 
############################################################################################################################################
sub importIntergenicAnnotations{
  my %args = @_;
  my $annotation_dir = $args{'-input_dir'};
  my $current_chromosome = $args{'-chromosome'};
  my $range = $args{'-range'};

  my $start_filter;
  my $end_filter;
  if ($range =~ /(\d+)\-(\d+)/){
    $start_filter = $1;
    $end_filter = $2;
  }else{
    print RED, "\nProblem with range - importIntergenicAnnotations()\n\n", RESET;
    exit();
  } 

  $| = 1; print BLUE, "\n3.) Parsing intergenic annotations from files in: $annotation_dir\n", RESET; $| = 0;
  print LOG "\n3.) Parsing intergenic annotations from files in: $annotation_dir\n";

  my %intergenics;
  my %active_regions;
  my %silent_regions;

  #Open annotation files
  my $intergenic_file = "$annotation_dir"."intergenics_annotated.txt.gz";
  my $active_file = "$annotation_dir"."activeIntergenicRegions.txt.gz";
  my $silent_file = "$annotation_dir"."silentIntergenicRegions.txt.gz";
  open (INTERGENIC, "zcat $intergenic_file |") || die "\nCould not open intergenic annotation file: $intergenic_file\n\n";  
  open (ACTIVE, "zcat $active_file |") || die "\nCould not open intergenic active region annotation file: $active_file\n\n";  
  open (SILENT, "zcat $silent_file |") || die "\nCould not open intergenic silent region annotation file: $silent_file\n\n";  

  #A.) INTERGENICS
  my $intergenic_count = 0;
  my $header = 1;
  my %columns;

  while(<INTERGENIC>){
    chomp($_);
    my $line = $_;
    my @line = split("\t", $line);

    if ($header == 1){
      $intergenic_header = $line;
      my $column_count = 0;
      foreach my $column (@line){
        $columns{$column}{column_pos} = $column_count;
        $column_count++;
      }
      $header = 0;
      next();
    }
    my $chr = $line[$columns{'Chromosome'}{column_pos}];
    my $intergenic_id = $line[$columns{'Intergenic_ID'}{column_pos}];
    my $strand = $line[$columns{'Strand'}{column_pos}];
    my $start_chr = $line[$columns{'Unit1_start_chr'}{column_pos}];
    my $end_chr = $line[$columns{'Unit1_end_chr'}{column_pos}];
    my $name = $line[$columns{'Seq_Name'}{column_pos}];
    my $unmasked_base_count = $line[$columns{'UnMasked_Base_Count'}{column_pos}];
    my $upstream_gene_id = $line[$columns{'Upstream_Gene_ID'}{column_pos}];
    my $downstream_gene_id = $line[$columns{'Downstream_Gene_ID'}{column_pos}];
 
    #Only store lines corresponding to the chromosome being processed
    unless ($chr eq $current_chromosome && ($start_chr >= $start_filter && $start_chr <= $end_filter && $end_chr >= $start_filter && $end_chr <= $end_filter)){
      next();
    }
    $intergenic_count++;

    if ($strand eq "1"){
      $strand = "+";
    }elsif($strand eq "-1"){
      $strand = "-";
    }else{
      $strand = ".";
    }
    $intergenics{$intergenic_id}{count} = $intergenic_count;
    $intergenics{$intergenic_id}{line} = $line;
    $intergenics{$intergenic_id}{chromosome} = $chr;
    $intergenics{$intergenic_id}{start} = $start_chr;
    $intergenics{$intergenic_id}{end} = $end_chr;
    $intergenics{$intergenic_id}{strand} = $strand;
    $intergenics{$intergenic_id}{name} = $name;
    $intergenics{$intergenic_id}{unmasked_base_count} = $unmasked_base_count;
    $intergenics{$intergenic_id}{upstream_gene_id} = $upstream_gene_id;
    $intergenics{$intergenic_id}{downstream_gene_id} = $downstream_gene_id;

    #Initialize result values...
    $intergenics{$intergenic_id}{expressed} = 0;
    $intergenics{$intergenic_id}{quality_read_count} = 0;
    $intergenics{$intergenic_id}{cumulative_coverage_raw} = 0;
    $intergenics{$intergenic_id}{cumulative_coverage_norm1} = 0;
    $intergenics{$intergenic_id}{percent_bases_covered_1x} = 0;
    $intergenics{$intergenic_id}{percent_bases_covered_5x} = 0;
    $intergenics{$intergenic_id}{percent_bases_covered_10x} = 0;
    $intergenics{$intergenic_id}{percent_bases_covered_100x} = 0;
    $intergenics{$intergenic_id}{average_coverage_raw} = 0;
    $intergenics{$intergenic_id}{average_coverage_norm1} = 0;
    my @tmp;
    $intergenics{$intergenic_id}{flank_genes} = \@tmp;

    my $ucsc_chromosome = "chr"."$chr";
    my $record_id = "$name"."__"."$intergenic_id";
    my $record = "\n$ucsc_chromosome\tEnsEMBL\tintergenic\t$start_chr\t$end_chr\t.\t.\t.\t$record_id";
    $ensembl_intergenic_tracks{$intergenic_count} = $record;
  }

  #B.) ACTIVE REGIONS
  my $active_count = 0;
  $header = 1;
  %columns = ();

  while(<ACTIVE>){
    chomp($_);
    my $line = $_;
    my @line = split("\t", $line);

    if ($header == 1){
      $active_header = $line;
      my $column_count = 0;
      foreach my $column (@line){
        $columns{$column}{column_pos} = $column_count;
        $column_count++;
      }
      $header = 0;
      next();
    }
    my $chr = $line[$columns{'Chromosome'}{column_pos}];
    my $ar_id = $line[$columns{'Active_Region_ID'}{column_pos}];
    my $intergenic_id = $line[$columns{'Intergenic_ID'}{column_pos}];
    my $strand = $line[$columns{'Strand'}{column_pos}];
    my $start_chr = $line[$columns{'Unit1_start_chr'}{column_pos}];
    my $end_chr = $line[$columns{'Unit1_end_chr'}{column_pos}];
    my $name = $line[$columns{'Seq_Name'}{column_pos}];
    my $unmasked_base_count = $line[$columns{'UnMasked_Base_Count'}{column_pos}];
  
    #Only store lines corresponding to the chromosome being processed AND where the corresponding Intergenic region has also been imported!
    unless ($chr eq $current_chromosome && ($start_chr >= $start_filter && $start_chr <= $end_filter && $end_chr >= $start_filter && $end_chr <= $end_filter) && $intergenics{$intergenic_id}){
      next();
    }
    $active_count++;
 
    if ($strand eq "1"){
      $strand = "+";
    }elsif($strand eq "-1"){
      $strand = "-";
    }else{
      $strand = ".";
    }
    $active_regions{$ar_id}{count} = $active_count;
    $active_regions{$ar_id}{line} = $line;
    $active_regions{$ar_id}{intergenic_id} = $intergenic_id;
    $active_regions{$ar_id}{chromosome} = $chr;
    $active_regions{$ar_id}{start} = $start_chr;
    $active_regions{$ar_id}{end} = $end_chr;
    $active_regions{$ar_id}{strand} = $strand;
    $active_regions{$ar_id}{name} = $name;
    $active_regions{$ar_id}{unmasked_base_count} = $unmasked_base_count;

    #Initialize result values...
    $active_regions{$ar_id}{expressed} = 0;
    $active_regions{$ar_id}{quality_read_count} = 0;
    $active_regions{$ar_id}{cumulative_coverage_raw} = 0;
    $active_regions{$ar_id}{cumulative_coverage_norm1} = 0;
    $active_regions{$ar_id}{percent_bases_covered_1x} = 0;
    $active_regions{$ar_id}{percent_bases_covered_5x} = 0;
    $active_regions{$ar_id}{percent_bases_covered_10x} = 0;
    $active_regions{$ar_id}{percent_bases_covered_100x} = 0;
    $active_regions{$ar_id}{average_coverage_raw} = 0;
    $active_regions{$ar_id}{average_coverage_norm1} = 0;
    my @tmp;
    $active_regions{$ar_id}{flank_genes} = \@tmp;

    my $ucsc_chromosome = "chr"."$chr";
    my $record_id = "$name"."__"."$ar_id";
    my $record = "\n$ucsc_chromosome\tEnsEMBL\tactiveRegion\t$start_chr\t$end_chr\t.\t.\t.\t$record_id";
    $ensembl_active_region_tracks{$active_count} = $record;
  }

  #C.) SILENT REGIONS
  my $silent_count = 0;
  $header = 1;
  %columns = ();

  while(<SILENT>){
    chomp($_);
    my $line = $_;
    my @line = split("\t", $line);

    if ($header == 1){
      $silent_header = $line;
      my $column_count = 0;
      foreach my $column (@line){
        $columns{$column}{column_pos} = $column_count;
        $column_count++;
      }
      $header = 0;
      next();
    }
    my $chr = $line[$columns{'Chromosome'}{column_pos}];
    my $sr_id = $line[$columns{'Silent_Region_ID'}{column_pos}];
    my $intergenic_id = $line[$columns{'Intergenic_ID'}{column_pos}];
    my $strand = $line[$columns{'Strand'}{column_pos}];
    my $start_chr = $line[$columns{'Unit1_start_chr'}{column_pos}];
    my $end_chr = $line[$columns{'Unit1_end_chr'}{column_pos}];
    my $name = $line[$columns{'Seq_Name'}{column_pos}];
    my $unmasked_base_count = $line[$columns{'UnMasked_Base_Count'}{column_pos}];

    #Only store lines corresponding to the chromosome being processed AND where the corresponding Intergenic region has also been imported!
    unless ($chr eq $current_chromosome && ($start_chr >= $start_filter && $start_chr <= $end_filter && $end_chr >= $start_filter && $end_chr <= $end_filter) && $intergenics{$intergenic_id}){
      next();
    }
    $silent_count++;

    if ($strand eq "1"){
      $strand = "+";
    }elsif($strand eq "-1"){
      $strand = "-";
    }else{
      $strand = ".";
    }
    $silent_regions{$sr_id}{count} = $silent_count;
    $silent_regions{$sr_id}{line} = $line;
    $silent_regions{$sr_id}{intergenic_id} = $intergenic_id;
    $silent_regions{$sr_id}{chromosome} = $chr;
    $silent_regions{$sr_id}{start} = $start_chr;
    $silent_regions{$sr_id}{end} = $end_chr;
    $silent_regions{$sr_id}{strand} = $strand;
    $silent_regions{$sr_id}{name} = $name;
    $silent_regions{$sr_id}{unmasked_base_count} = $unmasked_base_count;

    #Initialize result values...
    $silent_regions{$sr_id}{expressed} = 0;
    $silent_regions{$sr_id}{quality_read_count} = 0;
    $silent_regions{$sr_id}{cumulative_coverage_raw} = 0;
    $silent_regions{$sr_id}{cumulative_coverage_norm1} = 0;
    $silent_regions{$sr_id}{percent_bases_covered_1x} = 0;
    $silent_regions{$sr_id}{percent_bases_covered_5x} = 0;
    $silent_regions{$sr_id}{percent_bases_covered_10x} = 0;
    $silent_regions{$sr_id}{percent_bases_covered_100x} = 0;
    $silent_regions{$sr_id}{average_coverage_raw} = 0;
    $silent_regions{$sr_id}{average_coverage_norm1} = 0;
    my @tmp;
    $silent_regions{$sr_id}{flank_genes} = \@tmp;

    my $ucsc_chromosome = "chr"."$chr";
    my $record_id = "$name"."__"."$sr_id";
    my $record = "\n$ucsc_chromosome\tEnsEMBL\tsilentRegion\t$start_chr\t$end_chr\t.\t.\t.\t$record_id";
    $ensembl_silent_region_tracks{$silent_count} = $record;
  }

  #Close input files
  close (INTERGENIC);
  close (ACTIVE);
  close (SILENT);

  $| = 1; print BLUE, "\n\tFound $intergenic_count Intergenics, $active_count Active Intergenic Regions, and $silent_count Silent Intergenic Regions", RESET; $| = 0;
  print LOG "\n\tFound $intergenic_count Intergenics, $active_count Active Intergenic Regions, and $silent_count Silent Intergenic Regions";

  $intergenics_ref = \%intergenics;
  $active_regions_ref = \%active_regions;
  $silent_regions_ref = \%silent_regions;

  return();
}


############################################################################################################################################
#Get basic info for all genes from the user specified ALEXA database                                                                       #
############################################################################################################################################
sub getBasicGeneInfo{
  my %args = @_;
  my $target_chr = $args{'-chromosome'};
  my $range = $args{'-range'};

  print BLUE, "\n\n2-a.) Getting basic gene data", RESET;
  print LOG "\n\n2-a.) Getting basic gene data";

  #Establish connection with the Alternative Splicing Expression database
  my $alexa_dbh = &connectDB('-database'=>$database, '-server'=>$server, '-user'=>$user, '-password'=>$password);

  my @gene_ids = @{&getAllGenes ('-dbh'=>$alexa_dbh, '-gene_type'=>'All', '-chromosome'=>$target_chr, '-range'=>$range)};

  #Get the gene info for all genes for which reads were found on the current chromosome
  $genes_ref = &getGeneInfo ('-dbh'=>$alexa_dbh, '-gene_ids'=>\@gene_ids, '-sequence'=>"no");

  #Initialize some gene-level counters
  foreach my $gene_id (keys %{$genes_ref}){
    $genes_ref->{$gene_id}->{intergenic_count} = 0;
    $genes_ref->{$gene_id}->{intergenic_base_count} = 0;
    $genes_ref->{$gene_id}->{active_region_count} = 0;
    $genes_ref->{$gene_id}->{active_region_base_count} = 0;
    $genes_ref->{$gene_id}->{silent_region_count} = 0;
    $genes_ref->{$gene_id}->{silent_region_base_count} = 0;
    $genes_ref->{$gene_id}->{observed_intergenic_count} = 0;
    $genes_ref->{$gene_id}->{observed_active_count} = 0;
    $genes_ref->{$gene_id}->{observed_silent_count} = 0;
  }

  #Go through all the intergenic regions and get the previously determined, immediately adjacent, 'Upstream_Gene' and 'Downstream_Gene'
  #Assign these to the gene record
  #When generating a gene-level summary, only these intergenic regions will be considered
  #Furthermore, only these intergenic regions (and their corresponding active/silent regions) that are contained within a certain amount of flank will be counted

  #For Intergenics (IG), active regions (AIG) and silent regions (SIG) assign a list of genes where each of these things is completely contained within the gene+flank
  #Each IG, AIG, or SIG should be assigned to no more than 2 genes (closest one upstream, closest one downstream)
  #Many IG, AIG and SIG will not be within the flank of any genes...
  my $flank_distance = 10000;

  print BLUE, "\n\n2-b.) Determining Intergenic Regions, Active Regions and Silent Regions that are contained within $flank_distance from the end of their closest genes", RESET;
  print LOG "\n\n2-b.) Determining Intergenic Regions, Active Regions and Silent Regions that are contained within $flank_distance from the end of their closest genes";

  my $ig_flank_count = 0;
  my $aig_flank_count = 0;
  my $sig_flank_count = 0;

  #Find intergenics near genes (within $flank_distance of the end of a gene)
  foreach my $i_id (sort {$intergenics_ref->{$a}->{count} <=> $intergenics_ref->{$b}->{count}} keys %{$intergenics_ref}){
    my $upstream_gene_id = $intergenics_ref->{$i_id}->{upstream_gene_id};
    my $downstream_gene_id = $intergenics_ref->{$i_id}->{downstream_gene_id};

    my @genes;
    unless ($upstream_gene_id eq "NA" || $upstream_gene_id eq "na"){push(@genes, $upstream_gene_id);}
    unless ($downstream_gene_id eq "NA" || $downstream_gene_id eq "na"){push(@genes, $downstream_gene_id);}

    foreach my $gene_id (@genes){
      #Make sure this gene is defined in the current block of genes
      unless($genes_ref->{$gene_id}){
        next();
      }
      my $chr_start = $genes_ref->{$gene_id}->{chr_start};
      my $chr_end = $genes_ref->{$gene_id}->{chr_end};
      my $tmp;
      #print YELLOW, "\ngid: $gene_id\tchr_start: $chr_start\tchr_end: $chr_end", RESET;
      if ($chr_start > $chr_end){
        $tmp = $chr_start;
        $chr_start = $chr_end;
        $chr_end = $tmp;
      }
      my $flank_start = $chr_start - $flank_distance;
      my $flank_end = $chr_end + $flank_distance;

      #Does the flank completely encompass the current intergenic region - if so mark this gene_id in the intergenic region record
      my $i_start = $intergenics_ref->{$i_id}->{start};
      my $i_end = $intergenics_ref->{$i_id}->{end};
      if (($i_start >= $flank_start && $i_start <= $flank_end) && ($i_end >= $flank_start && $i_end <= $flank_end)){
        push(@{$intergenics_ref->{$i_id}->{flank_genes}}, $gene_id);
        $ig_flank_count++;
      }
    }
  }
  print BLUE, "\n\tFound $ig_flank_count such associations for Intergenic Regions", RESET;
  print LOG "\n\tFound $ig_flank_count such associations for Intergenic Regions";

  #Find active intergenic regions near genes (within $flank_distance of the end of a gene)
  foreach my $ar_id (sort {$active_regions_ref->{$a}->{count} <=> $active_regions_ref->{$b}->{count}} keys %{$active_regions_ref}){
    my $intergenic_id = $active_regions_ref->{$ar_id}->{intergenic_id}; 
    my $upstream_gene_id = $intergenics_ref->{$intergenic_id}->{upstream_gene_id};
    my $downstream_gene_id = $intergenics_ref->{$intergenic_id}->{downstream_gene_id};

    my @genes;
    unless ($upstream_gene_id eq "NA" || $upstream_gene_id eq "na"){push(@genes, $upstream_gene_id);}
    unless ($downstream_gene_id eq "NA" || $downstream_gene_id eq "na"){push(@genes, $downstream_gene_id);}

    foreach my $gene_id (@genes){
      #Make sure this gene is defined in the current block of genes
      unless($genes_ref->{$gene_id}){
        next();
      }

      my $chr_start = $genes_ref->{$gene_id}->{chr_start};
      my $chr_end = $genes_ref->{$gene_id}->{chr_end};
      my $tmp;
      if ($chr_start > $chr_end){
        $tmp = $chr_start;
        $chr_start = $chr_end;
        $chr_end = $tmp;
      }
      my $flank_start = $chr_start - $flank_distance;
      my $flank_end = $chr_end + $flank_distance;

      #Does the flank completely encompass the current active intergenic region - if so mark this gene_id in the active intergenic region record
      my $i_start = $active_regions_ref->{$ar_id}->{start};
      my $i_end = $active_regions_ref->{$ar_id}->{end};
      if (($i_start >= $flank_start && $i_start <= $flank_end) && ($i_end >= $flank_start && $i_end <= $flank_end)){
        push(@{$active_regions_ref->{$ar_id}->{flank_genes}}, $gene_id);
        $aig_flank_count++; 
      }
    }
  }
  print BLUE, "\n\tFound $aig_flank_count such associations for Active Intergenic Regions", RESET;
  print LOG "\n\tFound $aig_flank_count such associations for Active Intergenic Regions";

  #Find silent intergenic regions near genes (within $flank_distance of the end of a gene)
  foreach my $sr_id (sort {$silent_regions_ref->{$a}->{count} <=> $silent_regions_ref->{$b}->{count}} keys %{$silent_regions_ref}){
    my $intergenic_id = $silent_regions_ref->{$sr_id}->{intergenic_id}; 
    my $upstream_gene_id = $intergenics_ref->{$intergenic_id}->{upstream_gene_id};
    my $downstream_gene_id = $intergenics_ref->{$intergenic_id}->{downstream_gene_id};

    my @genes;
    unless ($upstream_gene_id eq "NA" || $upstream_gene_id eq "na"){push(@genes, $upstream_gene_id);}
    unless ($downstream_gene_id eq "NA" || $downstream_gene_id eq "na"){push(@genes, $downstream_gene_id);}

    foreach my $gene_id (@genes){
      #Make sure this gene is defined in the current block of genes
      unless($genes_ref->{$gene_id}){
        next();
      }
      my $chr_start = $genes_ref->{$gene_id}->{chr_start};
      my $chr_end = $genes_ref->{$gene_id}->{chr_end};
      my $tmp;
      if ($chr_start > $chr_end){
        $tmp = $chr_start;
        $chr_start = $chr_end;
        $chr_end = $tmp;
      }
      my $flank_start = $chr_start - $flank_distance;
      my $flank_end = $chr_end + $flank_distance;

      #Does the flank completely encompass the current silent intergenic region - if so mark this gene_id in the silent intergenic region record
      my $i_start = $silent_regions_ref->{$sr_id}->{start};
      my $i_end = $silent_regions_ref->{$sr_id}->{end};
      if (($i_start >= $flank_start && $i_start <= $flank_end) && ($i_end >= $flank_start && $i_end <= $flank_end)){
        push(@{$silent_regions_ref->{$sr_id}->{flank_genes}}, $gene_id);
        $sig_flank_count++; 
      }
    }
  }
  print BLUE, "\n\tFound $sig_flank_count such associations for Silent Intergenic Regions", RESET;
  print LOG "\n\tFound $sig_flank_count such associations for Silent Intergenic Regions";

  #Close database connection
  $alexa_dbh->disconnect();

  return();
}


#########################################################################################################################################
#build Chromosome and Gene Coverage Objects                                                                                             #
#########################################################################################################################################
sub buildCoverageObjects{
  my %args = @_;
  my $target_chr = $args{'-chromosome'};
  my $range = $args{'-range'};
  my $working_dir = $args{'-working_dir'};

  $| = 1; print BLUE, "\n\n4.) Building INTERGENIC coverage objects for chr$target_chr: $range", RESET; $| = 0;
  print LOG "\n\n4.) Building INTERGENIC coverage objects for chr$target_chr: $range";

  #Open the previously created berkeley DB object containing the reads of this chromosome - open in readonly mode
  $target_chr = "chr"."$target_chr";

  my $counter = 0;
  my $read_counter = 0;
  my $block_count = 0;
  my $block_size = 10000;

  while (my ($read_id) = each %chr_reads){

    $counter++;
    $read_counter++;

    if ($counter == $block_size){
      $block_count++;

      $| = 1; print BLUE, "\n\tProcessed block $block_count (of size $block_size reads) from the Berkley DB (for $target_chr: $range) - $read_counter reads so far", RESET; $| = 0;
      print LOG "\n\tProcessed block $block_count (of size $block_size reads) from the Berkley DB (for $target_chr: $range) - $read_counter reads so far";
      $counter = 0;
    }

    my $string = $chr_reads{$read_id};
    my @data = split("\t", $string);
    my $intergenic_id = $data[0];
    my $chr_start = $data[1];
    my $chr_end = $data[2];

    #Add coverage for intergenic
    if ($intergenics_ref->{$intergenic_id}){
      &addReadIntergenicCoverage('-intergenic_id'=>$intergenic_id, '-chr_start'=>$chr_start, '-chr_end'=>$chr_end);
    }

    #Add coverage for chromosome
    &addReadChrCoverage('-chr_start'=>$chr_start, '-chr_end'=>$chr_end);
  }

  return();
}


############################################################################################################################################
#Add the coverage of a read to an intergenic to the coverage hash for that intergenic
############################################################################################################################################
sub addReadIntergenicCoverage{
  my %args = @_;
  my $intergenic_id = $args{'-intergenic_id'};
  my $chr_start = $args{'-chr_start'};
  my $chr_end = $args{'-chr_end'};

  $intergenics_ref->{$intergenic_id}->{quality_read_count}++;

  #Go through each chromosome position in this read as it is mapped to an intergenic and increment that position in the hash
  my $bases_added = 0;
  for (my $i = $chr_start; $i <= $chr_end; $i++){

    my $intergenic_pos_id = "$intergenic_id"."_"."$i";

    if ($intergenic_coverage{$intergenic_pos_id}){
      $intergenic_coverage{$intergenic_pos_id}++;
      $bases_added++;
    }else{
      $intergenic_coverage{$intergenic_pos_id} = 1;
      $bases_added++;
    }
  }

  return();
}


############################################################################################################################################
#Add the coverage of a read to a intergenic to the coverage hash for the intergenic content record                                                 #
############################################################################################################################################
sub addReadChrCoverage{
  my %args = @_;
  my $chr_start = $args{'-chr_start'};
  my $chr_end = $args{'-chr_end'};

  #Go through each chromosome position in this read as it is mapped to an exon and increment that position in the hash
  for (my $i = $chr_start; $i <= $chr_end; $i++){
    my $pos_id = "$i";
    if ($chr_coverage{$pos_id}){
      $chr_coverage{$pos_id}++;
    }else{
      $chr_coverage{$pos_id} = 1;
    }
  }
  return();
}


############################################################################################################################################
#Correct base count values at the GENE and CHROMOSOME level - correct for library size and mappability                                     #
############################################################################################################################################
sub correctBaseCounts{
  my %args = @_;
  my $normalization_value = $args{'-normalization_value'};  #User specified normalization value (# quality mapped reads from smallest library)
  my $library_size = $args{'-library_size'};                #Actual library size according to input read file

  my $library_correction_ratio = 1;
  unless ($library_size == 0){
    $library_correction_ratio = $normalization_value/$library_size;
  }


  $| = 1; print BLUE, "\n\n5.) Correcting INTERGENIC and CHROMOSOME base counts for chr$chr_filter:$start_filter-$end_filter", RESET; $| = 0;
  print LOG "\n\n5.) Correcting INTERGENIC and CHROMOSOME base counts for chr$chr_filter:$start_filter-$end_filter";

  #A.) CHROMOSOME BASE CORRECTION
  #Correct for library size and mapability - store values in their respective hashes
  while (my ($pos) = each %chr_coverage){

    #First correct for library size
    my $coverage_val = $chr_coverage{$pos};
    my $corrected_val = $coverage_val*$library_correction_ratio;
    my $corrected_val_f = sprintf("%.10f", $corrected_val);
    $chr_coverage_norm1{$pos} = $corrected_val_f;
  }


  #B.) INTERGENIC BASE CORRECTION
  while (my ($intergenic_pos) = each %intergenic_coverage){

    if ($intergenic_pos =~ /(.*)\_(\d+)$/){
      my $intergenic_id = $1;
      my $pos = $2;

      #First correct for library size
      my $coverage_val = $intergenic_coverage{$intergenic_pos};
      my $corrected_val = $coverage_val*$library_correction_ratio;
      my $corrected_val_f = sprintf("%.10f", $corrected_val);
      $intergenic_coverage_norm1{$intergenic_pos} = $corrected_val_f;

    }else{
      print RED, "\nIntergenic_Pos value not understood! - (was: $intergenic_pos)\n\n", RESET;
      exit();
    }
  }
  return();
}


############################################################################################################################################
#Print out Gene, Intergenic, and ACTIVE/SILENT regions Summary files                                                                           #
############################################################################################################################################
sub printSummary{
  my %args = @_;
  my $results_dir = $args{'-results_dir'};

  unless ($web_path =~ /.*\/$/){
    $web_path = "$web_path"."/";
  }

  $| = 1; print BLUE, "\n\n6.) Printing Summary data to: $results_dir", RESET; $| = 0;
  print LOG "\n\n6.) Printing Summary data to: $results_dir";

  #A.) INTERGENIC EXPRESSION VALUES
  #CALCULATE CUMULATIVE INTERGENIC COVERAGE VALUES - USE THESE TO CALCULATE AVERAGE COVERAGE VALUES
  #The coverage of each base of each intergenic has been stored
  #Use this information to calculate the sequence coverage of each intergenic
  #Summarize the % of bases with at least 1X coverage and the overall average X coverage

  $| = 1; print BLUE, "\n\t6-a.) Summarizing sequence coverage of each intergenic ...\n", RESET; $| = 0;
  print LOG "\n\t6-a.) Summarizing sequence coverage of each intergenic ...\n";

  my $counter = 0;
  foreach my $i_id (sort {$intergenics_ref->{$a}->{count} <=> $intergenics_ref->{$b}->{count}} keys %{$intergenics_ref}){
    $counter++;
    if ($counter == 1000){
      $| = 1; print BLUE, ".", RESET; $| = 0;
      print LOG ".";
      $counter = 0;
    }

    #Traverse through the base positions of this intergenic content block and calculate the cumulative coverage
    my $cumulative_coverage_raw = 0;
    my $cumulative_coverage_norm1 = 0;
    my $bases_covered_1x = 0;
    my $bases_covered_5x = 0;
    my $bases_covered_10x = 0;
    my $bases_covered_100x = 0;

    my $start = $intergenics_ref->{$i_id}->{start};
    my $end = $intergenics_ref->{$i_id}->{end};
    my $strand = $intergenics_ref->{$i_id}->{strand};
    my $chr = $intergenics_ref->{$i_id}->{chromosome};
    my $name = $intergenics_ref->{$i_id}->{name};
    my $intergenic_base_count = $intergenics_ref->{$i_id}->{unmasked_base_count};

    for (my $i = $start; $i <= $end; $i++){
      my $intergenic_pos = "$i_id"."_"."$i";

      #Only continue if the current position was defined and had some coverage for this intergenic (masked positions will not be defined for example) 
      unless($intergenic_coverage{$intergenic_pos}){
        next();
      }
      my $coverage_raw = $intergenic_coverage{$intergenic_pos};
      $cumulative_coverage_raw += $coverage_raw;
      $cumulative_coverage_norm1 += $intergenic_coverage_norm1{$intergenic_pos};
      if ($coverage_raw >= 1){$bases_covered_1x++;}
      if ($coverage_raw >= 5){$bases_covered_5x++;}
      if ($coverage_raw >= 10){$bases_covered_10x++;}
      if ($coverage_raw >= 100){$bases_covered_100x++;}
    }

    #Store results in intergenic object 
    $intergenics_ref->{$i_id}->{cumulative_coverage_raw} = $cumulative_coverage_raw;
    $intergenics_ref->{$i_id}->{cumulative_coverage_norm1} = $cumulative_coverage_norm1;
    $intergenics_ref->{$i_id}->{bases_covered_1x} = $bases_covered_1x;

    #Watch out for regions with 0 unmasked bases!
    unless ($intergenic_base_count == 0){
      $intergenics_ref->{$i_id}->{percent_bases_covered_1x} = sprintf("%.2f", (($bases_covered_1x/$intergenic_base_count)*100));
      $intergenics_ref->{$i_id}->{percent_bases_covered_5x} = sprintf("%.2f", (($bases_covered_5x/$intergenic_base_count)*100));
      $intergenics_ref->{$i_id}->{percent_bases_covered_10x} = sprintf("%.2f", (($bases_covered_10x/$intergenic_base_count)*100));
      $intergenics_ref->{$i_id}->{percent_bases_covered_100x} = sprintf("%.2f", (($bases_covered_100x/$intergenic_base_count)*100));
      $intergenics_ref->{$i_id}->{average_coverage_raw} = sprintf("%.10f", ($cumulative_coverage_raw/$intergenic_base_count));
      $intergenics_ref->{$i_id}->{average_coverage_norm1} = sprintf("%.10f", ($cumulative_coverage_norm1/$intergenic_base_count));
    }
    my @gene_id_list = @{$intergenics_ref->{$i_id}->{flank_genes}};

    #Determine whether this element should be considered as expressed above background
    #In the case of overlap to multiple genes, it must exceed the greater cutoff
    #Note that for intergenic regions only the intergenic background level stored as gene '0' is used
    my $cutoff_test = 1;
    if ($cutoffs_file){
      my @result = @{&testExpression('-cutoffs_ref'=>$gene_cutoffs_ref, '-gene_id'=>'0', '-norm_expression_value'=>$intergenics_ref->{$i_id}->{average_coverage_norm1}, '-raw_expression_value'=>$intergenics_ref->{$i_id}->{average_coverage_raw}, '-percent_gene_expression_cutoff'=>0)};
      $cutoff_test = $result[0];
    }

    #Note if this intergenic is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
    if ($intergenics_ref->{$i_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
      $intergenics_ref->{$i_id}->{expressed} = 1;
      my $ucsc_chromosome = "chr"."$chr";
      my $record_id = "$name"."__"."$i_id";
      my $record = "\n$ucsc_chromosome\tEnsEMBL\texpressedIntergenic\t$start\t$end\t.\t.\t.\t$record_id";
      $intergenics_ref->{$i_id}->{expressed_record} = $record;
    }

    #If this intergenic region is within a specified distance from a gene:
    #Count this intergenic and its bases toward the total count for the gene (or multiple genes in the case of two genes separated by a small intergenic region)
    #Also, note if it is expressed above the level specified by the user - Use percent base coverage for this test
    foreach my $gene_id (@gene_id_list){
      $genes_ref->{$gene_id}->{intergenic_count}++; 
      $genes_ref->{$gene_id}->{intergenic_base_count} += $intergenic_base_count;

      #Also note if this intergenic is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
      if ($intergenics_ref->{$i_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
        $genes_ref->{$gene_id}->{observed_intergenic_count}++;
      }
    }

  }

  #B.) ACTIVE REGION EXPRESSION VALUES
  $| = 1; print BLUE, "\n\t6-a.) Summarizing sequence coverage of each active region ...\n", RESET; $| = 0;
  print LOG "\n\t6-a.) Summarizing sequence coverage of each active ...\n";

  $counter = 0;
  foreach my $ar_id (keys %{$active_regions_ref}){
    $counter++;
    if ($counter == 1000){
      $| = 1; print BLUE, ".", RESET; $| = 0;
      print LOG ".";
      $counter = 0;
    }

    #Traverse through the base positions of this intergenic content block and calculate the cumulative coverage
    my $cumulative_coverage_raw = 0;
    my $cumulative_coverage_norm1 = 0;
    my $bases_covered_1x = 0;
    my $bases_covered_5x = 0;
    my $bases_covered_10x = 0;
    my $bases_covered_100x = 0;

    my $start = $active_regions_ref->{$ar_id}->{start};
    my $end = $active_regions_ref->{$ar_id}->{end};
    my $strand = $active_regions_ref->{$ar_id}->{strand};
    my $chr = $active_regions_ref->{$ar_id}->{chromosome};
    my $name = $active_regions_ref->{$ar_id}->{name};
    my $ar_base_count = $active_regions_ref->{$ar_id}->{unmasked_base_count};
    my $intergenic_id = $active_regions_ref->{$ar_id}->{intergenic_id};

    for (my $i = $start; $i <= $end; $i++){
      my $ar_pos = "$intergenic_id"."_"."$i";

      #Only continue if the current position was defined and had some coverage for this intergenic (masked positions will not be defined for example) 
      unless($intergenic_coverage{$ar_pos}){
        next();
      }
      my $coverage_raw = $intergenic_coverage{$ar_pos};
      $cumulative_coverage_raw += $coverage_raw;
      $cumulative_coverage_norm1 += $intergenic_coverage_norm1{$ar_pos};
      if ($coverage_raw >= 1){$bases_covered_1x++;}
      if ($coverage_raw >= 5){$bases_covered_5x++;}
      if ($coverage_raw >= 10){$bases_covered_10x++;}
      if ($coverage_raw >= 100){$bases_covered_100x++;}
    }

    #Store results in active region object 
    $active_regions_ref->{$ar_id}->{cumulative_coverage_raw} = $cumulative_coverage_raw;
    $active_regions_ref->{$ar_id}->{cumulative_coverage_norm1} = $cumulative_coverage_norm1;
    $active_regions_ref->{$ar_id}->{bases_covered_1x} = $bases_covered_1x;

    #Watch out for regions with 0 unmasked bases!
    unless ($ar_base_count == 0){
      $active_regions_ref->{$ar_id}->{percent_bases_covered_1x} = sprintf("%.2f", (($bases_covered_1x/$ar_base_count)*100));
      $active_regions_ref->{$ar_id}->{percent_bases_covered_5x} = sprintf("%.2f", (($bases_covered_5x/$ar_base_count)*100));
      $active_regions_ref->{$ar_id}->{percent_bases_covered_10x} = sprintf("%.2f", (($bases_covered_10x/$ar_base_count)*100));
      $active_regions_ref->{$ar_id}->{percent_bases_covered_100x} = sprintf("%.2f", (($bases_covered_100x/$ar_base_count)*100));
      $active_regions_ref->{$ar_id}->{average_coverage_raw} = sprintf("%.10f", ($cumulative_coverage_raw/$ar_base_count));
      $active_regions_ref->{$ar_id}->{average_coverage_norm1} = sprintf("%.10f", ($cumulative_coverage_norm1/$ar_base_count));
    }

    my @gene_id_list = @{$active_regions_ref->{$ar_id}->{flank_genes}};

    #Determine whether this element should be considered as expressed above background
    #In the case of overlap to multiple genes, it must exceed the greater cutoff
    #Note that for intergenic regions only the intergenic background level stored as gene '0' is used
    my $cutoff_test = 1;
    if ($cutoffs_file){
      my @result = @{&testExpression('-cutoffs_ref'=>$gene_cutoffs_ref, '-gene_id'=>'0', '-norm_expression_value'=>$active_regions_ref->{$ar_id}->{average_coverage_norm1}, '-raw_expression_value'=>$active_regions_ref->{$ar_id}->{average_coverage_raw}, '-percent_gene_expression_cutoff'=>0)};
      $cutoff_test = $result[0];
    }

    #Note if this active region is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
    if ($active_regions_ref->{$ar_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
      $active_regions_ref->{$ar_id}->{expressed} = 1;
      my $ucsc_chromosome = "chr"."$chr";
      my $record_id = "$name"."__"."$ar_id";
      my $record = "\n$ucsc_chromosome\tEnsEMBL\texpressedAIG\t$start\t$end\t.\t.\t.\t$record_id";
      $active_regions_ref->{$ar_id}->{expressed_record} = $record;
    }

    #If this active region is within a specified distance from a gene:
    #Count this active region and its bases toward the total count for the gene (or multiple genes in the case of two genes separated by a small intergenic region)
    #Also, note if it is expressed above the level specified by the user - Use percent base coverage for this test
    foreach my $gene_id (@gene_id_list){
      $genes_ref->{$gene_id}->{active_region_count}++; 
      $genes_ref->{$gene_id}->{active_region_base_count} += $ar_base_count;

      #Also note if this active region is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
      if ($active_regions_ref->{$ar_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
        $genes_ref->{$gene_id}->{observed_active_count}++;
      }
    }

  }

  #B.) SILENT REGION EXPRESSION VALUES
  $| = 1; print BLUE, "\n\t6-a.) Summarizing sequence coverage of each silent region ...\n", RESET; $| = 0;
  print LOG "\n\t6-a.) Summarizing sequence coverage of each silent ...\n";

  $counter = 0;
  foreach my $sr_id (keys %{$silent_regions_ref}){
    $counter++;
    if ($counter == 1000){
      $| = 1; print BLUE, ".", RESET; $| = 0;
      print LOG ".";
      $counter = 0;
    }

    #Traverse through the base positions of this intergenic content block and calculate the cumulative coverage
    my $cumulative_coverage_raw = 0;
    my $cumulative_coverage_norm1 = 0;
    my $bases_covered_1x = 0;
    my $bases_covered_5x = 0;
    my $bases_covered_10x = 0;
    my $bases_covered_100x = 0;

    my $start = $silent_regions_ref->{$sr_id}->{start};
    my $end = $silent_regions_ref->{$sr_id}->{end};
    my $strand = $silent_regions_ref->{$sr_id}->{strand};
    my $chr = $silent_regions_ref->{$sr_id}->{chromosome};
    my $name = $silent_regions_ref->{$sr_id}->{name};
    my $sr_base_count = $silent_regions_ref->{$sr_id}->{unmasked_base_count};
    my $intergenic_id = $silent_regions_ref->{$sr_id}->{intergenic_id};

    for (my $i = $start; $i <= $end; $i++){
      my $sr_pos = "$intergenic_id"."_"."$i";

      #Only continue if the current position was defined and had some coverage for this intergenic (masked positions will not be defined for example) 
      unless($intergenic_coverage{$sr_pos}){
        next();
      }
      my $coverage_raw = $intergenic_coverage{$sr_pos};
      $cumulative_coverage_raw += $coverage_raw;
      $cumulative_coverage_norm1 += $intergenic_coverage_norm1{$sr_pos};
      if ($coverage_raw >= 1){$bases_covered_1x++;}
      if ($coverage_raw >= 5){$bases_covered_5x++;}
      if ($coverage_raw >= 10){$bases_covered_10x++;}
      if ($coverage_raw >= 100){$bases_covered_100x++;}
    }

    #Store results in silent region object 
    $silent_regions_ref->{$sr_id}->{cumulative_coverage_raw} = $cumulative_coverage_raw;
    $silent_regions_ref->{$sr_id}->{cumulative_coverage_norm1} = $cumulative_coverage_norm1;
    $silent_regions_ref->{$sr_id}->{bases_covered_1x} = $bases_covered_1x;
    
    #Watch out for regions with 0 unmasked bases!
    unless ($sr_base_count == 0){
      $silent_regions_ref->{$sr_id}->{percent_bases_covered_1x} = sprintf("%.2f", (($bases_covered_1x/$sr_base_count)*100));
      $silent_regions_ref->{$sr_id}->{percent_bases_covered_5x} = sprintf("%.2f", (($bases_covered_5x/$sr_base_count)*100));
      $silent_regions_ref->{$sr_id}->{percent_bases_covered_10x} = sprintf("%.2f", (($bases_covered_10x/$sr_base_count)*100));
      $silent_regions_ref->{$sr_id}->{percent_bases_covered_100x} = sprintf("%.2f", (($bases_covered_100x/$sr_base_count)*100));
      $silent_regions_ref->{$sr_id}->{average_coverage_raw} = sprintf("%.10f", ($cumulative_coverage_raw/$sr_base_count));
      $silent_regions_ref->{$sr_id}->{average_coverage_norm1} = sprintf("%.10f", ($cumulative_coverage_norm1/$sr_base_count));
    }

    my @gene_id_list = @{$silent_regions_ref->{$sr_id}->{flank_genes}};

    #Determine whether this element should be considered as expressed above background
    #In the case of overlap to multiple genes, it must exceed the greater cutoff
    #Note that for intergenic regions only the intergenic background level stored as gene '0' is used
    my $cutoff_test = 1;
    if ($cutoffs_file){
      my @result = @{&testExpression('-cutoffs_ref'=>$gene_cutoffs_ref, '-gene_id'=>'0', '-norm_expression_value'=>$silent_regions_ref->{$sr_id}->{average_coverage_norm1}, '-raw_expression_value'=>$silent_regions_ref->{$sr_id}->{average_coverage_raw}, '-percent_gene_expression_cutoff'=>0)};
      $cutoff_test = $result[0];
    }

    #Note if this silent region is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
    if ($silent_regions_ref->{$sr_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
      $silent_regions_ref->{$sr_id}->{expressed} = 1;
      my $ucsc_chromosome = "chr"."$chr";
      my $record_id = "$name"."__"."$sr_id";
      my $record = "\n$ucsc_chromosome\tEnsEMBL\texpressedSIG\t$start\t$end\t.\t.\t.\t$record_id";
      $silent_regions_ref->{$sr_id}->{expressed_record} = $record;
    }

    #If this silent region is within a specified distance from a gene:
    #Count this silent region and its bases toward the total count for the gene (or multiple genes in the case of two genes separated by a small intergenic region)
    #Also, note if it is expressed above the level specified by the user - Use percent base coverage for this test
    foreach my $gene_id (@gene_id_list){
      $genes_ref->{$gene_id}->{silent_region_count}++; 
      $genes_ref->{$gene_id}->{silent_region_base_count} += $sr_base_count;

      #Also note if this silent region is expressed according to the criteria specified by the user (% of of bases covered at 1x or greater)
      if ($silent_regions_ref->{$sr_id}->{percent_bases_covered_1x} >= $min_seq_coverage && $cutoff_test == 1){
        $genes_ref->{$gene_id}->{observed_silent_count}++;
      }
    }

  }

  #Write four results file
  $| = 1; print BLUE, "\n\t6-b.) Now printing the actual Gene and Intergenic summary lines for chr: $chr_filter: $start_filter-$end_filter ...\n", RESET; $| = 0;
  print LOG "\n\t6-b.) Now printing the actual Gene and Intergenic summary lines for chr: $chr_filter: $start_filter-$end_filter ...\n";

  #Set names of output result files
  my $gene_outfile = "$results_dir"."chr"."$file_name_prefix"."_IntergenicGeneSummary.txt";
  my $intergenic_outfile = "$results_dir"."chr"."$file_name_prefix"."_IntergenicExpression.txt";
  my $active_outfile = "$results_dir"."chr"."$file_name_prefix"."_ActiveIntergenicRegionExpression.txt";
  my $silent_outfile = "$results_dir"."chr"."$file_name_prefix"."_SilentIntergenicRegionExpression.txt";

  #A.) GENE-LEVEL.  Provides links to UCSC tracks.  ALEXA_ID, EnsEMBL_Gene_ID, IntergenicCount, IntergenicicBaseCount, ActiveRegionCount, SilentRegionCount, ObservedIntergenicCount, ObservedActiveRegionCount, ObservedSilentRegionCount
  open (GENE_OUT, ">$gene_outfile") || die "\nCould not open output gene summary file: $gene_outfile\n\n";
  print GENE_OUT "ALEXA_ID\tEnsEMBL_Gene_ID\tGene_Name\tDescription\tGene_Type\tGene_Evidence\tChromosome\tStrand\tStart\tEnd\tIntergenic_Count\tIntergenic_Base_Count\tActive_Region_Count\tActive_Region_Base_Count\tSilent_Region_Count\tSilent_Region_Base_Count\tObserved_Intergenic_Count\tObserved_Active_Region_Count\tObserved_Silent_Region_Count\tLink\n";

  #Go through each gene and print out basic data for it.  Also include a link to the custom track file for its chromosome
  foreach my $gene_id (sort {$a <=> $b} keys %{$genes_ref}){

    my $description = $genes_ref->{$gene_id}->{description};
    my $ensg_id = $genes_ref->{$gene_id}->{ensembl_g_id};

    #Create a link to go directly to the region of this gene (+/- 100bp) and load the correct chromosome file
    my $display_start = $genes_ref->{$gene_id}->{chr_start};
    my $display_end = $genes_ref->{$gene_id}->{chr_end};
    my $temp;
    if ($display_start > $display_end){
      $temp = $display_start;
      $display_start = $display_end;
      $display_end = $temp;
    }
    $display_start -= 100;
    $display_end += 100;

    my $chromosome = "chr"."$genes_ref->{$gene_id}->{chromosome}";

    #Link that retains pre-existing custom tracks
    #Clean link
    my $link = "http://genome.ucsc.edu/cgi-bin/hgTracks?db="."$ucsc_build"."&position=$chromosome:$display_start-$display_end&hgt.customText=$web_path"."chr$file_name_prefix"."_Intergenic.txt.gz&ctfile_"."$ucsc_build"."=";

    print GENE_OUT "$gene_id\t$ensg_id\t$genes_ref->{$gene_id}->{gene_name}\t$description\t$genes_ref->{$gene_id}->{gene_type}\t$genes_ref->{$gene_id}->{evidence}\t$genes_ref->{$gene_id}->{chromosome}\t$genes_ref->{$gene_id}->{chr_strand}\t$genes_ref->{$gene_id}->{chr_start}\t$genes_ref->{$gene_id}->{chr_end}\t$genes_ref->{$gene_id}->{intergenic_count}\t$genes_ref->{$gene_id}->{intergenic_base_count}\t$genes_ref->{$gene_id}->{active_region_count}\t$genes_ref->{$gene_id}->{active_region_base_count}\t$genes_ref->{$gene_id}->{silent_region_count}\t$genes_ref->{$gene_id}->{silent_region_base_count}\t$genes_ref->{$gene_id}->{observed_intergenic_count}\t$genes_ref->{$gene_id}->{observed_active_count}\t$genes_ref->{$gene_id}->{observed_silent_count}\t$link\n";

  }
  close(GENE_OUT);


  #B.) INTERGENICS.

  #Go through each intergenic (in the order in which they were read in from file) and append expression data to the input data
  open (INTERGENIC_OUT, ">$intergenic_outfile") || die "\nCould not open output intergenic summary file: $intergenic_outfile\n\n";
  print INTERGENIC_OUT "$intergenic_header\tRead_Count\tCumulative_Coverage\tAverage_Coverage_RAW\tAverage_Coverage_NORM1\tBases_Covered_1x\tPercent_Coverage_1x\tPercent_Coverage_5x\tPercent_Coverage_10x\tPercent_Coverage_100x\tExpressed\n";

  foreach my $i_id (sort {$intergenics_ref->{$a}->{count} <=> $intergenics_ref->{$b}->{count}} keys %{$intergenics_ref}){

   print INTERGENIC_OUT "$intergenics_ref->{$i_id}->{line}\t$intergenics_ref->{$i_id}->{quality_read_count}\t$intergenics_ref->{$i_id}->{cumulative_coverage_raw}\t$intergenics_ref->{$i_id}->{average_coverage_raw}\t$intergenics_ref->{$i_id}->{average_coverage_norm1}\t$intergenics_ref->{$i_id}->{bases_covered_1x}\t$intergenics_ref->{$i_id}->{percent_bases_covered_1x}\t$intergenics_ref->{$i_id}->{percent_bases_covered_5x}\t$intergenics_ref->{$i_id}->{percent_bases_covered_10x}\t$intergenics_ref->{$i_id}->{percent_bases_covered_100x}\t$intergenics_ref->{$i_id}->{expressed}\n"; 
  }
  close(INTERGENIC_OUT);


  #C.) ACTIVE INTERGENIC REGIONS

  #Go through each active region (in the order in which they were read in from file) and append expression data to the input data
  open (ACTIVE_OUT, ">$active_outfile") || die "\nCould not open output intergenic summary file: $active_outfile\n\n";
  print ACTIVE_OUT "$active_header\tCumulative_Coverage\tAverage_Coverage_RAW\tAverage_Coverage_NORM1\tBases_Covered_1x\tPercent_Coverage_1x\tPercent_Coverage_5x\tPercent_Coverage_10x\tPercent_Coverage_100x\tExpressed\n";

  foreach my $ar_id (sort {$active_regions_ref->{$a}->{count} <=> $active_regions_ref->{$b}->{count}} keys %{$active_regions_ref}){

   print ACTIVE_OUT "$active_regions_ref->{$ar_id}->{line}\t$active_regions_ref->{$ar_id}->{cumulative_coverage_raw}\t$active_regions_ref->{$ar_id}->{average_coverage_raw}\t$active_regions_ref->{$ar_id}->{average_coverage_norm1}\t$active_regions_ref->{$ar_id}->{bases_covered_1x}\t$active_regions_ref->{$ar_id}->{percent_bases_covered_1x}\t$active_regions_ref->{$ar_id}->{percent_bases_covered_5x}\t$active_regions_ref->{$ar_id}->{percent_bases_covered_10x}\t$active_regions_ref->{$ar_id}->{percent_bases_covered_100x}\t$active_regions_ref->{$ar_id}->{expressed}\n"; 
  }
  close(ACTIVE_OUT);


  #D.) SILENT INTERGENIC REGIONS

  #Go through each silent region (in the order in which they were read in from file) and append expression data to the input data
  open (SILENT_OUT, ">$silent_outfile") || die "\nCould not open output intergenic summary file: $silent_outfile\n\n";
  print SILENT_OUT "$silent_header\tCumulative_Coverage\tAverage_Coverage_RAW\tAverage_Coverage_NORM1\tBases_Covered_1x\tPercent_Coverage_1x\tPercent_Coverage_5x\tPercent_Coverage_10x\tPercent_Coverage_100x\tExpressed\n";
  foreach my $sr_id (sort {$silent_regions_ref->{$a}->{count} <=> $silent_regions_ref->{$b}->{count}} keys %{$silent_regions_ref}){

   print SILENT_OUT "$silent_regions_ref->{$sr_id}->{line}\t$silent_regions_ref->{$sr_id}->{cumulative_coverage_raw}\t$silent_regions_ref->{$sr_id}->{average_coverage_raw}\t$silent_regions_ref->{$sr_id}->{average_coverage_norm1}\t$silent_regions_ref->{$sr_id}->{bases_covered_1x}\t$silent_regions_ref->{$sr_id}->{percent_bases_covered_1x}\t$silent_regions_ref->{$sr_id}->{percent_bases_covered_5x}\t$silent_regions_ref->{$sr_id}->{percent_bases_covered_10x}\t$silent_regions_ref->{$sr_id}->{percent_bases_covered_100x}\t$silent_regions_ref->{$sr_id}->{expressed}\n"; 
  }
  close(SILENT_OUT);

  return();
}




############################################################################################################################################
#Print out UCSC track files
############################################################################################################################################
sub printUCSCTrack{
  my %args = @_;
  my $ucsc_dir = $args{'-ucsc_dir'};
  my $target_chr = $args{'-chr'};
  my $library = $args{'-library'};

  $target_chr = "chr"."$target_chr";

  unless ($ucsc_dir =~ /.*\/$/){
    $ucsc_dir = "$ucsc_dir"."/";
  }

  my $ucsc_file = "$ucsc_dir"."chr$file_name_prefix"."_Intergenic.txt";
  #Print out all the UCSC track records gathered above for this chromosome
  open (UCSC, ">$ucsc_file") || die "\nCould not open ucsc file: $ucsc_file\n\n";

  $| = 1; print BLUE, "\n\n7.) Printing UCSC file for $target_chr: $ucsc_file", RESET; $| = 0;
  print LOG "\n\n7.) Printing UCSC file for $target_chr: $ucsc_file";

  #Browser line
  print UCSC "#Browser line";
  print UCSC "\nbrowser hide all";
  print UCSC "\nbrowser full knownGene";
  print UCSC "\nbrowser pack multiz28way";

  my $database_abr = $database;
  if ($database =~ /ALEXA_(\w+)/){
    $database_abr = $1;
  }


  #ANNOTATION TRACKS
  #1.) ANNOTATION Track line for EnsEMBL intergenics of each gene
  print UCSC "\n\n#EnsEMBL intergenics";
  my $track_name = "Intergenics";
  my $track_description = "\"EnsEMBL Intergenics used for Mapping ($database_abr)\"";
  $priority_annotation++;

  print UCSC "\ntrack name=$track_name description=$track_description color=$colors{$color_set}{1} useScore=0 visibility=0 priority=$priority_annotation";
  print UCSC "\n\n#Begin DATA\n";

  foreach my $record_id (sort {$a <=> $b} keys %ensembl_intergenic_tracks){
    my $record = $ensembl_intergenic_tracks{$record_id};
    print UCSC "$record";
  }

  #2.) ANNOTATION Track line for active intergenic regions of each gene
  print UCSC "\n\n#Active intergenic regions";
  $track_name = "Intergenic_ARs";
  $track_description = "\"Active regions annotated within EnsEMBL Intergenics (based on mRNAs/ESTs)\"";

  $priority_annotation++;
  print UCSC "\ntrack name=$track_name description=$track_description color=$colors{$color_set}{0} useScore=0 visibility=3 priority=$priority_annotation";
  print UCSC "\n\n#Begin DATA\n";

  foreach my $record_id (sort {$a <=> $b} keys %ensembl_active_region_tracks){
    my $record = $ensembl_active_region_tracks{$record_id};
    print UCSC "$record";
  }

  #3.) ANNOTATION Track line for silent intergenic regions of each gene
  print UCSC "\n\n#Silent intergenic regions";
  $track_name = "Intergenic_SRs";
  $track_description = "\"Silent regions annotated within EnsEMBL Intergenics (based on mRNAs/ESTs)\"";

  $priority_annotation++;
  print UCSC "\ntrack name=$track_name description=$track_description color=$colors{$color_set}{1} useScore=0 visibility=0 priority=$priority_annotation";
  print UCSC "\n\n#Begin DATA\n";

  foreach my $record_id (sort {$a <=> $b} keys %ensembl_silent_region_tracks){
    my $record = $ensembl_silent_region_tracks{$record_id};
    print UCSC "$record";
  }


  #EXPRESSED REGION TRACKS

  #4.) Expressed intergenics
  print UCSC "\n\n#EnsEMBL Expressed intergenics";
  my $eig_track_name = "$library"."_Exp_IG";
  my $eig_track_description = "\"Expressed EnsEMBL Intergenics (>= $min_seq_coverage% coverage and above intergenic background cutoff) ($library_name - $database_abr)\"";
  $priority_expression++;
  print UCSC "\ntrack name=$eig_track_name description=$eig_track_description color=$colors{$color_set}{2} useScore=0 visibility=3 priority=$priority_expression";
  print UCSC "\n\n#Begin DATA\n";

  foreach my $i_id (sort {$intergenics_ref->{$a}->{count} <=> $intergenics_ref->{$b}->{count}} keys %{$intergenics_ref}){
    if ($intergenics_ref->{$i_id}->{expressed} == 1){
      my $record = $intergenics_ref->{$i_id}->{expressed_record};
      print UCSC "$record";
    }
  }

  #5.) Expressed Active Regions
  print UCSC "\n\n#Expressed Active Intergenic Regions";
  my $eaig_track_name = "$library"."_Exp_AIG";
  my $eaig_track_description = "\"Expressed Active Intergenic Regions (>= $min_seq_coverage% coverage and above intergenic background cutoff) ($library_name - $database_abr)\"";

  print UCSC "\ntrack name=$eaig_track_name description=$eaig_track_description color=$colors{$color_set}{2} useScore=0 visibility=3 priority=$priority_expression";
  print UCSC "\n\n#Begin DATA\n";
  $priority_expression++;
  foreach my $ar_id (sort {$active_regions_ref->{$a}->{count} <=> $active_regions_ref->{$b}->{count}} keys %{$active_regions_ref}){
    if ($active_regions_ref->{$ar_id}->{expressed} == 1){
      my $record = $active_regions_ref->{$ar_id}->{expressed_record};
      print UCSC "$record";
    }
  }

  #6.) Expressed Silent Regions
  print UCSC "\n\n#Expressed Silent Intergenic Regions";
  my $esig_track_name = "$library"."_Exp_SIG";
  my $esig_track_description = "\"Expressed Silent Intergenic Regions (>= $min_seq_coverage% coverage and above intergenic background cutoff) ($library_name - $database_abr)\"";

  print UCSC "\ntrack name=$esig_track_name description=$esig_track_description color=$colors{$color_set}{2} useScore=0 visibility=3 priority=$priority_expression";
  print UCSC "\n\n#Begin DATA\n";
  $priority_expression++;
  foreach my $sr_id (sort {$silent_regions_ref->{$a}->{count} <=> $silent_regions_ref->{$b}->{count}} keys %{$silent_regions_ref}){
    if ($silent_regions_ref->{$sr_id}->{expressed} == 1){
      my $record = $silent_regions_ref->{$sr_id}->{expressed_record};
      print UCSC "$record";
    }
  }


  #WIGGLE TRACKS
  my $wig_track_name;
  my $wig_track_description;
  my $current_pos;
  my $first_block;

  #4.) Create a WIG track line to display the RAW coverage level for every intergenic base sequenced to 1X or greater depth
#  print UCSC "\n\n#WIG TRACK: RAW Intergenic Coverage calculated from Illumina Paired Reads Mapped to EnsEMBL Intergenics (masked)";
#  $wig_track_name = "$library"."_RAW_IG";
#  $wig_track_description = "\"RAW Intergenic Coverage. Paired Reads mapped to EnsEMBL Intergenics ($library_name - $database_abr)\"";
#  $priority_wiggle++;

#  print UCSC "\ntrack name=$wig_track_name description=$wig_track_description type=wiggle_0 color=$colors{$color_set}{2} yLineMark=0.0 yLineOnOff=on visibility=hide autoScale=on graphType=bar smoothingWindow=off maxHeightPixels=120:80:10 priority=$priority_expression";
#  print UCSC "\n\n#Begin DATA\n";

#  $current_pos = -1;
#  $first_block = 1;
#  foreach my $pos (sort {$a <=> $b} keys %chr_coverage){
    #If this is a new block of covered bases, print out a new def line
#    if ($pos == ($current_pos+1)){
#      print UCSC "\n$chr_coverage{$pos}";
#    }else{
#      unless($first_block == 1){
#        print UCSC "\n0.00"; #end each block with an arbitrary small value - for display purposes only
#      }
#      my $pos_minus_1 = $pos-1;
#      print UCSC "\nfixedStep chrom=$target_chr start=$pos_minus_1 step=1";
#      print UCSC "\n0.00"; #Start each block with an arbitrary small value - for display purposes only
#      print UCSC "\n$chr_coverage{$pos}";
#      $first_block = 0;
#    }
#    $current_pos = $pos;
#  }


  #5.) Create a WIG track line to display the NORM1 coverage level for every intergenic base sequenced to 1X or greater depth
  #    - NORM1 = library size adjusted values
  print UCSC "\n\n#WIG TRACK: Normalized Intergenic Coverage calculated from Illumina Paired Reads Mapped to EnsEMBL Transcripts";
  $wig_track_name = "$library"."_N1_IG";
  $wig_track_description = "\"Normalized Intergenic Coverage. Paired reads mapped to EnsEMBL Intergenics ($library_name - $database_abr)\"";
  $priority_wiggle++;

  print UCSC "\ntrack name=$wig_track_name description=$wig_track_description type=wiggle_0 color=$colors{$color_set}{2} yLineMark=0.0 yLineOnOff=on visibility=full autoScale=on graphType=bar smoothingWindow=off maxHeightPixels=120:80:10 priority=$priority_expression";
  print UCSC "\n\n#Begin DATA\n";

  $current_pos = -1;
  $first_block = 1;
  foreach my $pos (sort {$a <=> $b} keys %chr_coverage_norm1){

    my $val = $chr_coverage_norm1{$pos};

    #If this is a new block of covered bases, print out a new def line
    if ($pos == ($current_pos+1)){
      print UCSC "\n$val";
    }else{
      unless($first_block == 1){
        print UCSC "\n0.00"; #end each block with an arbitrary small value - for display purposes only
      }
      my $pos_minus_1 = $pos-1;
      print UCSC "\nfixedStep chrom=$target_chr start=$pos_minus_1 step=1";
      print UCSC "\n0.00"; #Start each block with an arbitrary small value
      print UCSC "\n$val";
      $first_block = 0;
    }
    $current_pos = $pos;
  }

  close(UCSC);

  #Finally gzip the file
  my $cmd = "gzip -f $ucsc_file";
  system($cmd);

  return();
}



