#!/usr/bin/perl
#
# This script will transform tophat's junction.bed file to actual junction coordinates
#
# Rodrigo Goya

use strict;

my $BED_FILE = $ARGV[0] || "-";

my $line_number = 0;
open(BED, "<$BED_FILE") || die("ERROR: could not open junction bed file: '$BED_FILE'\n");
while(<BED>) {
	chomp; s///;
	#chr3	189881601	189888428	JUNC00064306	4	+	189881601	189888428	255,0,0	2	20,29	0,6798
	my @f = split(/\t/, $_);
	$line_number++;

	if(!($f[0] =~ m/^chr/)) {next; }
	my $blocks = $f[9];
	if($blocks == 1) { next; }

	my $start = $f[1];
	my @b_sizes = split(/,/, $f[10]);
	my @b_offsets = split(/,/, $f[11]);
	for(my $b = 1; $b < $blocks; $b++) {
		my $left = $start + $b_offsets[$b-1] + $b_sizes[$b-1];
		my $right = $start + $b_offsets[$b] + 1;

		print "$f[0]:$left-$right\t$f[4]\n";
	}
}
close(BED);
