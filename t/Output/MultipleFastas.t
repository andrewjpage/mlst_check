#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp;
use File::Slurp;
use Cwd;
use Data::Dumper;
use String::Util 'trim';

BEGIN { unshift(@INC, './lib') }
BEGIN {
    use Test::Most;
    use_ok('Bio::MLST::Check');
}

my $tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
my $tmpdirectory = $tmpdirectory_obj->dirname();

ok((my $multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1
)),'Initialise single valid fasta');
ok(($multiple_fastas->create_result_files),'create all the results files for a single valid fasta');
compare_files($tmpdirectory.'/mlst_results.genomic.csv', 't/data/expected_mlst_results.genomic.csv');
compare_files($tmpdirectory.'/mlst_results.allele.csv', 't/data/expected_mlst_results.allele.csv');
compare_files($tmpdirectory.'/concatenated_alleles.fa', 't/data/expected_concatenated_alleles.fa');

$tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa','t/data/contigs_pipe_character_in_seq_name.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1
)),'Initialise 2 files, one with pipe char and no hits');
ok(($multiple_fastas->create_result_files),'create all the results files for two fastas');
compare_files($tmpdirectory.'/mlst_results.genomic.csv', 't/data/expected_two_mlst_results.genomic.csv');
compare_files($tmpdirectory.'/mlst_results.allele.csv', 't/data/expected_two_mlst_results.allele.csv');
compare_files($tmpdirectory.'/concatenated_alleles.fa', 't/data/expected_two_concatenated_alleles.fa');

$tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa','t/data/contigs_check_concat_allele_order.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1
)),'Initialise 2 files, check consistent allele ordering in concatenated results');
ok(($multiple_fastas->create_result_files),'correctly sort alleles in concatenated fasta');
compare_files($tmpdirectory.'/mlst_results.genomic.csv', 't/data/expected_sorted_mlst_results.genomic.csv');
compare_files($tmpdirectory.'/mlst_results.allele.csv', 't/data/expected_sorted_mlst_results.allele.csv');
compare_files($tmpdirectory.'/concatenated_alleles.fa', 't/data/expected_sorted_concatenated_alleles.fa');

sub get_sequences_from_file {

  my($FILE) = @_;

  my @sequences = ();
  my $line_number = 0;
  my $number_of_known_sequences = 0;

  while( my $line = <$FILE> ) {
    my $trimmed_line = trim($line);
    if ($number_of_known_sequences == 0) {
      # We don't know how many sequences there are so create a new one
      push( @sequences, [$trimmed_line]);
      # The first time we find a blank 'sequence' we now know the number of sequences
      if ($trimmed_line eq '') {
        $number_of_known_sequences = $line_number + 1;
      }
    } else {
      # Now that we know the number of sequences, append this line to it's corresponding sequence
      my $sequence_number = $line_number % $number_of_known_sequences;
      push( @{$sequences[$sequence_number]}, $trimmed_line);
    }
    $line_number++;
  }

  return @sequences;

}

sub compare_phylip_files {
  my($calculated_file, $expected_file) = @_;

  open(my $CALC_FILE, $calculated_file);
  open(my $EXPECTED_FILE, $expected_file);

  my $calculated_file_header = <$CALC_FILE>;
  my $expected_file_header = <$EXPECTED_FILE>;

  is($calculated_file_header, $expected_file_header, "Header matches expected value in ".$expected_file);

  my @calculated_file_sequences = sort({ $a->[0] cmp $b->[0] } get_sequences_from_file($CALC_FILE));
  my @expected_file_sequences = sort({ $a->[0] cmp $b->[0] } get_sequences_from_file($EXPECTED_FILE));

  close($CALC_FILE);
  close($EXPECTED_FILE);

  is_deeply(\@calculated_file_sequences, \@expected_file_sequences, "Sequences match ".$expected_file);

}

$tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa','t/data/contigs_pipe_character_in_seq_name.fa','t/data/contigs_one_unknown.tfa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  output_phylip_files   => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 3,
  report_lowest_st      => 1
)),'Initialise 3 files where 1 has near matches');
ok(($multiple_fastas->create_result_files),'create all the results files for three fastas');
compare_files( $tmpdirectory.'/mlst_results.genomic.csv',    't/data/expected_three_mlst_results.genomic.csv' );
compare_files( $tmpdirectory.'/mlst_results.allele.csv',     't/data/expected_three_mlst_results.allele.csv' );
compare_files( $tmpdirectory.'/concatenated_alleles.fa',     't/data/expected_three_concatenated_alleles.fa');
###
compare_phylip_files( $tmpdirectory.'/concatenated_alleles.phylip', 't/data/expected_three_concatenated_alleles.phylip' );
compare_files( $tmpdirectory.'/contigs_one_unknown.unknown_allele.adk-2~.fa',  't/data/expected_three_contigs_one_unknown.unknown_allele.adk-2~.fa' );
compare_files( $tmpdirectory.'/contigs_one_unknown.unknown_allele.recA-1~.fa', 't/data/expected_three_contigs_one_unknown.unknown_allele.recA-1~.fa');


$tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1
)),'Initialise on existing fasta file.');
my $files_exist = $multiple_fastas->input_fasta_files_exist;
ok($files_exist,'test fasta file exists - returns true for existing file');

$tmpdirectory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 1);
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($multiple_fastas = Bio::MLST::Check->new(
  species               => "E.coli",
  base_directory        => 't/data/databases',
  raw_input_fasta_files => ['t/data/contigs.fa','t/data/contigs_pipe_character_in_seq_name.fa','t/data/contigs_one_unknown.tfa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  output_phylip_files   => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 3
)),'Initialise 3 files where 1 has near matches and report best');
ok(($multiple_fastas->create_result_files),'create all the best results files for three fastas');
compare_files( $tmpdirectory.'/mlst_results.genomic.csv',    't/data/expected_three_mlst_best_results.genomic.csv' );
compare_files( $tmpdirectory.'/mlst_results.allele.csv',     't/data/expected_three_mlst_best_results.allele.csv' );

done_testing();

sub compare_files
{
  my( $actual_file, $expected_file ) = @_;
  ok((-e $actual_file),' results file exist');
  ok((-e $expected_file)," $expected_file expected file exist");
  
  my $expected_line =  read_file($expected_file);
  my $actual_line = read_file($actual_file);
  $expected_line =~ s/ \n//gi;
  $actual_line   =~ s/ \n//gi;
  
  # parallel processes mean the order isnt guaranteed.
  my @split_expected  = split(/\n/,$expected_line);
  my @split_actual  = split(/\n/,$actual_line);
  my @sorted_expected = sort(@split_expected);
  my @sorted_actual  = sort(@split_actual);
  
  return is_deeply(\@sorted_actual, \@sorted_expected, "Content matches expected $expected_file");
}
