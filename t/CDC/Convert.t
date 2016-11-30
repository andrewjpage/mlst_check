#!/usr/bin/env perl
use strict;
use warnings;
use Cwd;

BEGIN { unshift(@INC, './lib') }
BEGIN {
    use Test::Most;
    use Bio::MLST::Check;
    use_ok('Bio::MLST::CDC::Convert');
}

note('Allow for S. pyogenes emm typing files from the CDC to be used. Not techically an MLST scheme, but quite similar.');

my $destination_directory_obj = File::Temp->newdir( CLEANUP => 1, DIR => getcwd );
my $destination_directory = $destination_directory_obj->dirname();

# take in a fasta file, split it into alleles and profile
ok((my $convert_fasta = Bio::MLST::CDC::Convert->new(
  species        => 'Streptococcus pyogenes emmST',
  input_file     => 't/data/CDC_emmST_partial.tfa',
  gene_name      => 'emmST',
  base_directory => $destination_directory
  )),'Prepare the emmST coverter with a valid allele file.');

ok(($convert_fasta->create_mlst_files), 'Create the files for emmST.');
ok((-e $destination_directory.'/Streptococcus_pyogenes_emmST/alleles/emmST.tfa'), 'A FASTA file should be created for the allele in the correct directory and naming scheme.');
ok((-e $destination_directory.'/Streptococcus_pyogenes_emmST/profiles/Streptococcus_pyogenes_emmST.txt'), 'A profile file should be created for the allele in the correct directory and naming scheme.');

compare_files('t/data/databases/Streptococcus_pyogenes_emmST/alleles/emmST.tfa', $destination_directory.'/Streptococcus_pyogenes_emmST/alleles/emmST.tfa');
compare_files('t/data/databases/Streptococcus_pyogenes_emmST/profiles/Streptococcus_pyogenes_emmST.txt', $destination_directory.'/Streptococcus_pyogenes_emmST/profiles/Streptococcus_pyogenes_emmST.txt' );


# Check the the converted files can be used
my $tmpdirectory_obj = File::Temp->newdir( CLEANUP => 1, DIR => getcwd );
my $tmpdirectory = $tmpdirectory_obj->dirname();

ok((my $check_converted_files_obj = Bio::MLST::Check->new(
  species               => "Streptococcus pyogenes emmST",
  base_directory        => $destination_directory,
  raw_input_fasta_files => ['t/data/Streptococcus_pyogenes_emmST_contigs.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1,
  show_contamination_instead_of_alt_matches => 0,
)),'Pass in the converted files and perform a lookup to check it can be used');
ok(($check_converted_files_obj->create_result_files),'Create the output files from a given emmST assembly');

compare_files('t/data/expected_Streptococcus_pyogenes_emmST.genomic.csv', $tmpdirectory.'/mlst_results.genomic.csv');
compare_files('t/data/expected_Streptococcus_pyogenes_emmST.allele.csv', $tmpdirectory.'/mlst_results.allele.csv');
compare_files('t/data/expected_Streptococcus_pyogenes_emmST_alleles.fa', $tmpdirectory.'/concatenated_alleles.fa');


# unknown allele (single base change) should be picked up in concat output
$tmpdirectory_obj = File::Temp->newdir( CLEANUP => 1, DIR => getcwd );
$tmpdirectory = $tmpdirectory_obj->dirname();
ok(($check_converted_files_obj = Bio::MLST::Check->new(
  species               => "Streptococcus pyogenes emmST",
  base_directory        => $destination_directory,
  raw_input_fasta_files => ['t/data/Streptococcus_pyogenes_emmST_contigs.fa','t/data/Streptococcus_pyogenes_emmST_unknown.fa'],
  makeblastdb_exec      => 'makeblastdb',
  blastn_exec           => 'blastn',
  output_directory      => $tmpdirectory,
  output_fasta_files    => 1,
  spreadsheet_basename  => 'mlst_results',
  parallel_processes    => 1,
  show_contamination_instead_of_alt_matches => 0,
)),'Pass in an assembly with a known emmST and another assembly with an unknown one.');
ok(($check_converted_files_obj->create_result_files),'Create the output files from a given emmST assembly');

compare_files('t/data/expected_Streptococcus_pyogenes_emmST_alleles_with_unknown.fa', $tmpdirectory.'/concatenated_alleles.fa');



ok((my $convert_fasta_ftp = Bio::MLST::CDC::Convert->new(
  species        => 'Streptococcus pyogenes emmST',
  input_file     => 'ftp://example.com/file.fa',
  gene_name      => 'emmST',
  base_directory => $destination_directory
  )),'Setup the converter class and remote downloader');
ok(($convert_fasta_ftp->input_file), 'Check that the remote url was acceptable.');


done_testing();

sub compare_files
{
  my($expected_file, $actual_file) = @_;
  ok((-e $actual_file),' results file exist');
  ok((-e $expected_file)," $expected_file expected file exist");
  local $/ = undef;
  open(EXPECTED, $expected_file);
  open(ACTUAL, $actual_file);
  my $expected_line = <EXPECTED>;
  my $actual_line = <ACTUAL>;
  
  # parallel processes mean the order isnt guaranteed.
  my @split_expected  = split(/\n/,$expected_line);
  my @split_actual  = split(/\n/,$actual_line);
  my @sorted_expected = sort(@split_expected);
  my @sorted_actual  = sort(@split_actual);
  
  is_deeply(\@sorted_actual,\@sorted_expected, "Content matches expected $expected_file");
}
