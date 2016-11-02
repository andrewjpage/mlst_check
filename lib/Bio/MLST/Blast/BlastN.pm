package Bio::MLST::Blast::BlastN;
# ABSTRACT: Wrapper around NCBI BlastN

=head1 SYNOPSIS

Wrapper around NCBI BlastN. Run NCBI blast and find the top hit.

   use Bio::MLST::Blast::BlastN;
   
   my $blast_database= Bio::MLST::Blast::BlastN->new(
     blast_database => 'output_contigs',
     query_file     => 'alleles/adk.tfa',
     word_size      => 500,
     exec           => 'blastn'
   );
   $blast_database->top_hit();

=method top_hit

Returns a hash containing details about the top blast result.

The attributes returned in the hash are:
  allele_name
  percentage_identity
  source_name
  source_start
  source_end
  reverse
  contamination

=head1 SEE ALSO

=for :list
* L<Bio::MLST::Blast::Database>

=cut

use Moose;
use Bio::MLST::Types;
use List::Util qw(reduce max min);

# input variables
has 'blast_database'     => ( is => 'ro', isa => 'Str', required => 1 ); 
has 'query_file'         => ( is => 'ro', isa => 'Str', required => 1 ); 
has 'word_sizes'         => ( is => 'ro', isa => 'HashRef', required => 1 ); 
has 'exec'               => ( is => 'ro', isa => 'Bio::MLST::Executable', default  => 'blastn' ); 
has 'perc_identity'      => ( is => 'ro', isa => 'Int', default  => 0 );

# Generated
has 'top_hit'           => ( is => 'ro', isa => 'Maybe[HashRef]', lazy => 1,  builder => '_build_top_hit' ); 

sub _build_hit
{
  my($self, $line) = @_;
  chomp($line);
  my @row = split(/\t/,$line);
  my ($start, $end) = ($row[8], $row[9]);
  ($start, $end, my $reverse) = $start <= $end ? ($start, $end, 0) : ($end, $start, 1);
  return {
    'allele_name' => $row[0],
    'source_name' => $row[1],
    'percentage_identity' => $row[2],
    'sample_alignment_length' => $row[3],
    'matches' => $row[12],
    'source_start' => $start,
    'source_end' => $end,
    'reverse' => $reverse,
  };
}

sub _build_hits
{
  my ($self, $blast_output_fh) = @_;
  my @hits;
  while(<$blast_output_fh>)
  {
    push(@hits, $self->_build_hit($_));
  }
  return \@hits;
}

sub _filter_by_alignment_length
{
  ###
  # For each allele there is a minimum length of sequence it must be aligned
  # against before it can be considered a match.
  ###
  my ($self, $hits, $word_sizes) = @_;
  my @long_hits = grep { $_->{'sample_alignment_length'} >= $word_sizes->{$_->{'allele_name'}} } @$hits;
  return \@long_hits;
}

sub _filter_best_hits
{
  my($self, $hits, $tollerance) = @_;
  $tollerance = defined($tollerance) ? $tollerance : 2.0;
  my @percentages = map { $_->{'percentage_identity'} } @$hits;
  my $top_percentage = max @percentages;
  my @top_hits = grep { $_->{'percentage_identity'} >= $top_percentage - $tollerance } @$hits;
  return \@top_hits;
}

sub _group_overlapping_hits
{
  ###
  # Hits can overlap, this groups hits which overlap and returns a reference to
  # an array of references to these groups.
  ###
  my($self, $hits) = @_;
  my @bins = ();
  foreach my $hit (@$hits)
  {
    my $found_a_bin = 0;
    foreach my $bin (@bins)
    {
      # check if hit is in bin
      if (($hit->{'source_start'} >= $bin->{'start'}) and ($hit->{'source_end'} <= $bin->{'end'}))
      {
        push(@{$bin->{'hits'}}, $hit);
        $found_a_bin = 1;
        last;
      }
      # check if bin is in hit
      elsif (($hit->{'source_start'} <= $bin->{'start'}) and ($hit->{'source_end'} >= $bin->{'end'}))
      {
        push(@{$bin->{'hits'}}, $hit);
        $bin->{'start'} = $hit->{'source_start'};
        $bin->{'end'} = $hit->{'source_end'};
        $found_a_bin = 1;
        last;
      }
    }
    # If we've not found a bin for this hit, make a new one
    if (!$found_a_bin)
    {
      my $new_bin = {
        'start' => $hit->{'source_start'},
        'end' => $hit->{'source_end'},
        'hits' => [$hit]
      };
      push(@bins, $new_bin);
    }
  }
  return \@bins;
}

sub _merge_similar_bins
{
  ###
  # Some alleles differ from others due to indels at their beginning or end,
  # this merges the bins if they have a lot of overlap
  ###
  my ($self, $bins_ref) = @_;
  my @bins = sort { $a->{'start'} <=> $b->{'start'} } @$bins_ref;
  my $previous_bin = shift @bins;
  my @combined_bins = $previous_bin;
  my $bin;
  foreach $bin (@bins) {
    # Check if there is any overlap between the new_bin and the previous_bin
    my $overlap = max (0, ($previous_bin->{'end'} - $bin->{'start'}));
    my $length = min(($bin->{'end'} - $bin->{'start'}), ($previous_bin->{'end'} - $previous_bin->{'start'})) + 1;
    my $overlap_prop = $overlap / $length;
    if ($overlap_prop > 0.9) {
      $previous_bin->{'end'} = $bin->{'end'};
      push(@{$previous_bin->{'hits'}}, @{$bin->{'hits'}});
    } else {
      push( @combined_bins, $bin);
      $previous_bin = $bin;
    }
  }
  return \@combined_bins;
}

sub _bins_to_groups
{
  my($self, $bins) = @_;
  my @groups = map { $_->{hits} } @$bins;
  return \@groups;
}

sub _best_hit_in_group
{
  ###
  # The best hit has the greatest number of matching bases.  If two hits have
  # the same number of matching bases, the one with the greater
  # percentage identity is selected.
  ###
  my($self, $hits) = @_;
  my @lengths = map { $_->{'matches'} } @$hits;
  my $max_length = max @lengths;
  my @longest_hits = grep { $_->{'matches'} == $max_length } @$hits;

  my $best_hit = reduce { $a->{'percentage_identity'} > $b->{'percentage_identity'} ? $a : $b } @longest_hits;
  return $best_hit;
}

sub _blastn_cmd
{
  my($self) = @_;
  my $word_size = int(100/(100 - $self->perc_identity ));
  $word_size = 11 if($word_size < 11);
  my $outfmt = "\"6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore nident\""; # standard format + n. identical base matches
  
  join(' ',($self->exec, '-task blastn', '-query', $self->query_file, '-db', $self->blast_database, '-outfmt', $outfmt, '-word_size', $word_size , '-perc_identity', $self->perc_identity ));
}

sub _build_top_hit
{
  my($self) = @_;
  my $top_hit = {};
  my @contaminants = ();
  open(my $copy_stderr_fh, ">&STDERR"); open(STDERR, '>/dev/null'); # Redirect STDERR
  open( my $blast_output_fh, '-|',$self->_blastn_cmd);
  close(STDERR); open(STDERR, ">&", $copy_stderr_fh); # Restore STDERR

  # Find all of the best non-overlapping matches
  my $hits = $self->_build_hits($blast_output_fh);
  $hits = $self->_filter_by_alignment_length($hits, $self->word_sizes);
  my $best_hits = $self->_filter_best_hits($hits);
  my $bins = $self->_group_overlapping_hits($best_hits);
  $bins = $self->_merge_similar_bins($bins);
  my $groups = $self->_bins_to_groups($bins);

  # Find the best match
  my @best_in_groups = map { $self->_best_hit_in_group($_) } @$groups;
  $top_hit = reduce { $a->{'percentage_identity'} > $b->{'percentage_identity'} ? $a : $b } @best_in_groups;

  if (defined $top_hit)
  {
    $top_hit->{'percentage_identity'} = int($top_hit->{'percentage_identity'});
    delete $top_hit->{'sample_alignment_length'};
    delete $top_hit->{'matches'};
  }
  else {
    $top_hit = {};
  }
  if ( scalar @best_in_groups > 1 )
  {
    $top_hit->{contamination} = \@best_in_groups;
  }
  
  return $top_hit;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
