package WormBase::API::Object::Gene;

use Moose;
use File::Spec::Functions qw(catfile catdir);
use namespace::autoclean -except => 'meta';

extends 'WormBase::API::Object';
with    'WormBase::API::Role::Object';
with    'WormBase::API::Role::Position';

#####################

=pod 

=head1 NAME

WormBase::API::Object::Gene

=head1 SYNPOSIS

Model for the Ace ?Gene class.

=head1 URL

http://wormbase.org/species/*/gene

=head1 METHODS/URIs

=cut

has '_all_proteins' => (
    is  => 'ro',
    lazy => 1,
    default => sub {
        return [
            map { $_->Corresponding_protein(-fill => 1) }
                shift->object->Corresponding_CDS
        ];
    }
);

has 'sequences' => (
    is  => 'ro',
    lazy => 1,
    builder => '_build_sequences',
);

sub _build_sequences {
	my $self = shift;
	my $gene = $self->object;
    my %seen;
    my @seqs = grep { !$seen{$_}++} $gene->Corresponding_transcript;
    for my $cds ($gene->Corresponding_CDS) {
        next if defined $seen{$cds};
        my @transcripts = grep {!$seen{$cds}++} $cds->Corresponding_transcript;
        push (@seqs, @transcripts ? @transcripts : $cds);
    }
    return \@seqs if @seqs;
    return [$gene->Corresponding_Pseudogene];
}

has 'tracks' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return {
            description => 'tracks displayed in GBrowse',
            data        => shift->_parsed_species =~ /elegans/ ?
                           [qw(CG CANONICAL Allele RNAi)] : [qw/CG/],
        };
    }
);

has '_rnai_results' => (
    is => 'ro',
    lazy => 1,
    builder => '_build__rnai_results',
);

sub _build__rnai_results {
    my ($self) = @_;

    my %results; # rnai_result -> phenotypes, genotypes/strain, reference

    for my $rnai ($self->object->RNAi_result) {
        $results{$rnai}{object} = $self->_pack_obj($rnai);

        if (my $ref = $rnai->Reference) {
            $results{$rnai}{reference} = $self->_pack_obj($ref);
        }

        if (my $genotype = $rnai->Genotype || eval { $rnai->Strain->Genotype }) {
            $results{$rnai}{genotype} = "$genotype";
        }

        # phenotype data

        my @phenotypes = (
            $rnai->Phenotype,
            map { $_->right }
                grep { $_ eq 'Interaction_phenotype' }
                map  { $_->col }
                map  { $_->Interaction_type }
                $rnai->Interaction(-filltag => 'Interaction_type'),
        );

        my @phenotypes_nobs = $rnai->Phenotype_not_observed;

        $results{$rnai}{phenotypes_observed} = $self->_pack_objects(\@phenotypes)
            if @phenotypes;
        $results{$rnai}{phenotypes_not_observed} = $self->_pack_objects(\@phenotypes_nobs)
            if @phenotypes_nobs;
    }

    return \%results;
}

has '_phenotypes' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build__phenotypes',
);

sub _build__phenotypes {
    my ($self) = @_;
    my $object = $self->object;

    my %phenotypes;

    # gather xgene info
    for my $xgene ($object->Drives_Transgene, $object->Transgene_product) {
        my $packed_xgene = $self->_pack_obj($xgene);

        foreach ($xgene->Phenotype) {
            $phenotypes{observed}{$_}{object}          //= $self->_pack_obj($_);
            $phenotypes{observed}{$_}{transgene}{$xgene} = $packed_xgene;
        }

        foreach ($xgene->Phenotype_not_observed) {
            $phenotypes{not_observed}{$_}{object}          //= $self->_pack_obj($_);
            $phenotypes{not_observed}{$_}{transgene}{$xgene} = $packed_xgene;
        }
    }

    # gather variation info
    for my $allele ($object->Allele) {
        my $seq_status = $allele->SeqStatus;

        my $packed_allele = $self->_pack_obj($allele);
        $packed_allele->{boldface} = $seq_status && $seq_status =~ /sequenced/i;

        foreach ($allele->Phenotype) {
            $phenotypes{observed}{$_}{object}        //= $self->_pack_obj($_);
            $phenotypes{observed}{$_}{allele}{$allele} = $packed_allele;
        }

        foreach ($allele->Phenotype_not_observed) {
            $phenotypes{not_observed}{$_}{object}        //= $self->_pack_obj($_);
            $phenotypes{not_observed}{$_}{allele}{$allele} = $packed_allele
        }

        # ?Variation /Rescued/ ...
    }

    # extract rnai info
    while (my ($rnai, $rnai_details) = each %{$self->_rnai_results}) {
        for my $obs (qw(observed not_observed)) {
            my $phentype = 'phenotypes_' . $obs;
            next unless $rnai_details->{$phentype};
            while (my ($phenotype, $packed_pheno) = each %{$rnai_details->{$phentype}}) {
                $phenotypes{$obs}{$phenotype}{object}    //= $packed_pheno;
                # $phenotypes{$obs}{$phenotype}{rnai}{$rnai} = $rnai_details->{object};
                $phenotypes{$obs}{$phenotype}{rnai_count}++;
            }
        }
    }

    return \%phenotypes;
}

#######################################
#
# The Overview Widget
#   template: classes/gene/overview.tt2
#
#######################################

=head2 Overview

=cut

=head3 also_refers_to

This method will return a data structure containing
other names that have also been used to refer to the
gene.

=over

=item PERL API

 $data = $model->also_refers_to();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/also_refers_to

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub also_refers_to {
    my $self   = shift;
    my $object = $self->object;
    my $locus  = $object->CGC_name;

    my $pattern = qr/$object/;
    # Save other names that don't correspond to the current object.
    my @other_names_for = !$locus ? () :
        map { $self->_pack_obj($_) } grep { !/$pattern/ } $locus->Other_name_for;

    return {
        description => 'other genes that this locus name may refer to',
        data        => @other_names_for ? \@other_names_for : undef,
    };
}


=head3 classification

This method will return a data structure containing
the general classification of the gene.

=over

=item PERL API

 $data = $model->classification();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/classification

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub classification {
    my $self   = shift;
    my $object = $self->object;

    my $data;

    $data->{defined_by_mutation} = $object->Allele ? 1 : 0;

    # General type: coding gene, pseudogene, or RNA
    $data->{type} = 'pseudogene' if $object->Corresponding_pseudogene;

    # Protein coding?
    my @cds = $object->Corresponding_CDS;
    if (@cds) {
        my $status = $cds[0]->Prediction_status ? 'confirmed' : 'unconfirmed';
        $data->{type} = "protein coding ($status)";
    }

    # Is this a non-coding RNA?
    my @transcripts = $object->Corresponding_transcript;
    foreach (@transcripts) {
        $data->{type} = $_->Transcript;
        last;
    }

    $data->{associated_sequence} = @cds ? 1 : 0;

    # Confirmed?
    $data->{confirmed} = @cds ? $cds[0]->Prediction_status->name : 0;
    my $matching_cdna = @cds ? $cds[0]->Matching_cDNA : '';

    # Create a prose description; possibly better in a template.
    my @prose;
    if (   $data->{locus}
        && $data->{associated_sequence} )
    {
        push @prose,
            "This gene has been defined mutationally and associated with a sequence.";
    }
    elsif ( $data->{associated_sequence} ) {
        push @prose, "This gene is known only by sequence.";
    }
    elsif ( $data->{locus} ) {
        push @prose, "This gene is known only by mutation.";
    }
    else { }

    # Is the locus name approved?
    if ( $data->{locus} && $data->{approved_name} ) {
        push @prose, "The gene name has been approved by the CGC.";
    }
    elsif ( $data->{locus} && !$data->{approved_name} ) {
        push @prose, "The gene name has not been approved by the CGC.";
    }

    # Confirmed or not?
    if ( $data->{confirmed} eq 'Confirmed' ) {
        push @prose, "Gene structures have been confirmed by a curator.";
    }
    elsif ($matching_cdna) {
        push @prose,
            "Gene structures have been partially confirmed by matching cDNA.";
    }
    else {
        push @prose, "Gene structures have not been confirmed.";
    }

    $data->{prose_description} = join( " ", @prose );

    return {
        description => 'gene type and status',
        data        => $data,
    };
}


=head3 cloned_by

This method will return a data structure containing
the person or laboratory who cloned the gene.

=over

=item PERL API

 $data = $model->cloned_by();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/cloned_by

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub cloned_by {
    my $self      = shift;

    my $datapack = {
        description => 'the person or laboratory who cloned this gene',
        data        => undef,
    };

    # This is an evidence hash. We're assuming scalar context.
    if (my $cloned_by = $self->object->Cloned_by) {
        my ($tag,$source) = $cloned_by->row;
        $datapack->{data} = {
            'cloned_by' => "$cloned_by",
            'tag'       => "$tag",
            'source'    => $self->_pack_obj($source),
        };
    }

    return $datapack;
}


=head3 concise_desciption

This method will return a data structure containing
the prose concise description of the gene, if one exists.

=over

=item PERL API

 $data = $model->concise_description();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/concise_description

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub concise_description {
    my $self   = shift;
    my $object = $self->object;  
    
    my $description = 
	$object->Concise_description
	|| eval {$object->Corresponding_CDS->Concise_description}
        || eval { $object->Gene_class->Description }
        || $self->name->{data}->{label} . ' gene';
    
    return {
	description => "A manually curated description of the gene's function",
	data        => "$description" };
}


=head3 legacy_information

This method will return a data structure containing
legacy information from the original Cold Spring Harbor
C. elegans I & II texts.

=over

=item PERL API

 $data = $model->legacy_information();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/legacy_information

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub legacy_information {
  my $self   = shift;
  my $object = $self->object;
  my @description = map {"$_"} $object->Legacy_information;
  return { description => 'legacy information from the CSHL Press C. elegans I/II books',
	   data        => @description ? \@description : undef };
}

=head3 locus_name

This method will return a data structure containing
the name of the genetic locus.

=over

=item PERL API

 $data = $model->locus_name();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/locus_name

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub locus_name {
    my $self   = shift;
    my $locus  = $self->object->CGC_name;

    return {
        description => 'the locus name (also known as the CGC name) of the gene',
        data        => $locus ? $self->_pack_obj($locus->CGC_name_for, $locus->name) : undef
    };
}


# sub name {}
# Supplied by Role; POD will automatically be inserted here.
# << include name >>

# sub other_names {}
# Supplied by Role; POD will automatically be inserted here.
# << include other_names >>


=head3 sequence_name

This method will return a data structure containing
the primary sequence name of the gene.

=over

=item PERL API

 $data = $model->sequence_name();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/sequence_name

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub sequence_name {
    my $self     = shift;
    my $sequence = $self->object->Sequence_name;

    return {
        description => 'the primary corresponding sequence name of the gene, if known',
        data        => $sequence ? $self->_pack_obj($sequence->Sequence_name_for, "$sequence") : undef
    };
}


# sub status {}
# Supplied by Role; POD will automatically be inserted here.
# << include status >>

=head3 version

This method will return a data structure containing
various structured descriptions of gene's function.

=over

=item PERL API

 $data = $model->structured_description();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/structured_description

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub structured_description {
   my $self = shift;
   my %ret;
   my @types = qw(Provisional_description 
                  Other_description
                  Sequence_features
                  Functional_pathway 
                  Functional_physical_interaction 
                  Molecular_function
                  Sequence_features
                  Biological_process
                  Expression
                  Detailed_description);
   foreach my $type (@types){
      my $node = $self->object->$type or next;
      my @nodes = $self->object->$type;
      my $index=-1;
      @nodes = map {$index++; {text=>"$_", evidence=> {tag => $type,index=>$index, check => $self->check_empty($_)}}} @nodes;
      $ret{$type} = \@nodes if (@nodes > 0);
   }
   return { description => "structured descriptions of gene function",
	    data        =>  %ret ? \%ret : undef };
}

# sub taxonomy {}
# Supplied by Role; POD will automatically be inserted here.
# << include taxonomy >>


=head3 version

This method will return a data structure containing
the current WormBase version of the gene.

=over

=item PERL API

 $data = $model->version();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/version

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub version {
    return {
        description => 'the current WormBase version of the gene',
        data        => scalar eval { shift->object->Version->name },
    };
}



#######################################
#
# The Expression Widget
#   template: classes/gene/expression.tt2
#
#   TH: Several of the methods in this widget
#       need to be rewritten and clarified.
#
#######################################

=head2 Expression

=cut

=head3 fourd_expression_movies

This method will return a data structure containing
links to four-dimensional expression movies.

=over

=item PERL API

 $data = $model->fourd_expression_movies();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/fourd_expression_movies

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub fourd_expression_movies {
    my $self   = shift;

    my $author;
    my %data = map {
        my $details = $_->Pattern;
        my $url     = $_->MovieURL;
        $_ => {
            movie   => $url && "$url",
            details => $details && "$details",
            object  => $self->_pack_obj($_),
        };
    } grep {
        (($author = $_->Author) && $author =~ /Mohler/ && $_->MovieURL)
    } @{$self ~~ '@Expr_pattern'};

    return {
        description => 'interactive 4D expression movies',
        data        => %data ? \%data : undef,
    };
}


=head3 anatomic_expression_patterns

This method will return a complex data structure 
containing expression patterns described at the
anatomic level. Includes links to images.

=over

=item PERL API

 $data = $model->anatomic_expression_patterns();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/anatomic_expression_patterns

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub anatomic_expression_patterns {
    my $self   = shift;
    my $object = $self->object;
    my %data_pack;

    my $file = catfile($self->pre_compile->{gene_expr}, "$object.jpg");
    $data_pack{"image"}="jpg?class=gene_expr&id=$object"   if (-e $file && ! -z $file);

    # All expression patterns except Mohlers, presented elsewhere.
    my @eps = grep { !(($_->Author || '') =~ /Mohler/ && $_->MovieURL) }
                   $object->Expr_pattern;

    foreach my $ep (@eps) {
        my $file = catfile($self->pre_compile->{expr_object}, "$ep.jpg");
        $data_pack{"expr"}{"$ep"}{image}="jpg?class=expr_object&id=$ep" if (-e $file && ! -z $file);
        # $data_pack{"image"}{"$ep"}{image} = $self->_pattern_thumbnail($ep);
        my $pattern =  ($ep->Pattern(-filled=>1) || '') . ($ep->Subcellular_localization(-filled=>1) || '');
        $pattern    =~ s/(.{384}).+/$1.../;
        $data_pack{"expr"}{"$ep"}{details} = $pattern;
        $data_pack{"expr"}{"$ep"}{object} = $self->_pack_obj($ep);
    }

    return {
        description => 'expression patterns for the gene',
        data        => %data_pack ? \%data_pack : undef,
    };
}

=head3 microarray_expression_data
    
This method will return a data structure containing
microarray expression data.
    
=over

=item PERL API

 $data = $model->microarray_expression_data();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/microarray_expression_data

B<Response example>

<div class="response-example"></div>

=back

=cut 


sub microarray_expression_data {
    my $self   = shift;
    my $object = $self->object;
    my %data;
    my @microarray_results = $object->Microarray_results;	
    return { data        => @microarray_results ? $self->_pack_objects(\@microarray_results) : undef,
	     description => 'gene expression determined via microarray analysis'};
}

=head3 microrarray_topology_map_position

This method will return a data structure containing
the microarray "topology" map position.

=over

=item PERL API

 $data = $model->microarray_topology_map_position();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/microarray_topology_map_position

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub microarray_topology_map_position {
    my $self   = shift;
    my $object = $self->object;

    my $datapack = {
        description => 'microarray topology map',
        data        => undef,
    };

    return $datapack unless @{$self->sequences};
    my @segments = $self->_segments && @{$self->_segments} or return $datapack;
    my @p = map { $_->info }
            $segments[0]->features('experimental_result_region:Expr_profile')
        or return $datapack;
    my %data = map {
        $_ => $self->_pack_obj($_, eval { 'Mountain ' . $_->Expr_map->Mountain })
    } @p;

    $datapack->{data} = \%data if %data;
    return $datapack;
}

=head3 expression_cluster

This method will return a data structure containing
microarray expression clusters.

=over

=item PERL API

 $data = $model->expression_cluster();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/expression_cluster

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub expression_cluster {
    my $self   = shift;
    my $object = $self->object;
    my @expr_clusters = $object->Expression_cluster;  
    return { data        => @expr_clusters ? $self->_pack_objects(\@expr_clusters) : undef,
	     description => 'expression cluster data' };
}


=head3 anatomy_function

This method will return a data structure containing
the anatomy function of the gene.

=over

=item PERL API

 $data = $model->anatomy_function();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/anatomy_function

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub anatomy_function {
    my $self   = shift;
    my $object = $self->object;

    my @data;
    my @anatomy_fns = $object->Anatomy_function;
    foreach my $anatomy_fn (@anatomy_fns){
      my %anatomy_fn_data;
      my $afn_bodypart_set = $anatomy_fn->Body_part;
      if($afn_bodypart_set =~ m/Not_involved/){
          next;
      }
      else{
          my $afn_phenotype = $anatomy_fn->Phenotype;
          $anatomy_fn_data{'anatomy_fn'} = $self->_pack_obj($anatomy_fn);
          $anatomy_fn_data{'phenotype'} = $self->_pack_obj($afn_phenotype); #$phenotype_prime_name;
          my @afn_bodyparts = $afn_bodypart_set->col if $afn_bodypart_set;
          my @ao_terms;
          foreach my $afn_bodypart (@afn_bodyparts){
            my $ao_term_details;
            my @afn_bp_row = $afn_bodypart->row;
            my ($ao_id,$sufficiency,$description) = @afn_bp_row;
            if( ($sufficiency=~ m/Insufficient/)){
                next;
            }
            else{
                my $term = $ao_id->Term;
                $ao_term_details = $self->_pack_obj($term);
            }
            push @ao_terms,$ao_term_details;
          }
          $anatomy_fn_data{'terms'} = \@ao_terms;
      }
      push @data, \%anatomy_fn_data;
    }

    return { description =>  "anatomy function",
         data        =>  @data ? \@data : undef };

}




#######################################
#
# The External Links widget
#   template: shared/widgets/xrefs.tt2
#
#######################################

=head2 External Links

=cut

# sub xrefs {}
# Supplied by Role; POD will automatically be inserted here.
# << include xrefs >>


#######################################
#
# The Genetics Widget
#   template: classes/gene/genetics.tt2
#
#######################################

=head2 Genetics

=cut

=head3 alleles

This method will return a complex data structure 
containing alleles of the gene (but not including
polymorphisms or other natural variations.

=over

=item PERL API

 $data = $model->alleles();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/alleles

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub alleles {
    my $self   = shift;
    my $object = $self->object;
    my @alleles = $object->Allele;
    
    my @data;
    foreach my $allele (@alleles) {
	next if ($allele->Variation_type =~ /SNP/ || $allele->Variation_type =~ /RFLP/);
	push @data,$self->_process_variation($allele);       
    }
    
    return { description => 'alleles found within this gene',
	     data        => @data ? \@data : undef };
}

=head3 polymorphisms

This method will return a complex data structure 
containing polymorphisms and natural variations
but not alleles.

=over

=item PERL API

 $data = $model->polymorphisms();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/polymorphisms

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub polymorphisms {
    my $self    = shift;
    my $object  = $self->object;
    my @alleles = $object->Allele;
    
    my @data;
    foreach my $allele (@alleles) {
	next unless ($allele->Variation_type =~ /SNP/ || $allele->Variation_type =~ /RFLP/);
	push @data,$self->_process_variation($allele);
    }
    
    return { description => 'polymorphisms and natural variations found within this gene',
	     data        => @data ? \@data : undef };
}

# Private method: glean some information about a variation.
sub _process_variation {
    my ( $self, $variation ) = @_;

    my $type = lc( $variation->Variation_type ) || 'unknown';

    my $molecular_change = lc( $variation->Type_of_mutation || "other" );
    my $sequence_known = $variation->Flanking_sequences ? 'yes' : 'no';

    my $affects;
    foreach my $type_affected ( $variation->Affects ) {
        foreach my $item_affected ( $type_affected->col ) {    # is a subtree
            ($affects) = $item_affected->col;
        }
    }

    $type = "transposon insertion" if $variation->Transposon_insertion;

    my %data = (
        variation        => $self->_pack_obj($variation),
        type             => "$type",
        molecular_change => "$molecular_change",
        sequence_known   => $sequence_known,
        affects          => $affects && lc $affects,
    );
    return \%data;
}

=head3 reference_allele

This method will return a complex data structure 
containing the reference allele of the gene, if
one exists.

=over

=item PERL API

 $data = $model->reference_allele();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/reference_allele

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub reference_allele {
    my $self = shift;
    my $ref_alleles = $self ~~ '@Reference_allele' ;
    
    my @array = map { $self->_pack_obj($_) } @$ref_alleles;
    return { description => 'the reference allele of the gene',
	     data        => @array ? \@array : undef };
}

=head3 strains

This method will return a complex data structure 
containing strains carrying the gene.

=over

=item PERL API

 $data = $model->strains();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/strains

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub strains {
    my $self   = shift;

    my @data;
    my %count;
    foreach ($self->object->Strain) {
        my @genes = $_->Gene;
        my $cgc   = ($_->Location eq 'CGC') ? 1 : 0;

        my $packed = $self->_pack_obj($_);

        # All of the counts can go away if
        # we discard the venn diagram.
        push @{$count{total}},$packed;
        push @{$count{available_from_cgc}},$packed if $cgc;

        if (@genes == 1 && !$_->Transgene) {
            push @{$count{carrying_gene_alone}},$packed;
            if ($cgc) {
                push @{$count{carrying_gene_alone_and_cgc}},$packed;
            }
        }
        else {
            push @{$count{others}},$packed;
        }

        my $genotype = $_->Genotype;
        push @data, {
            strain   => $packed,
            cgc      => $cgc ? 'yes' : 'no',
            genotype => $genotype && "$genotype",
        };
    }

    return {
        description => 'strains carrying this gene',
        data        => @data ? \@data : undef,
        count       => %count ? \%count : undef,
    };
}

=head3 rearrangements
    
This method will return a data structure 
containing rearrangements affecting the gene.

=over

=item PERL API

 $data = $model->rearrangements();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/rearrangements

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub rearrangements {
    my $self    = shift;     
    my $object  = $self->object;
    my @positive = map { $self->_pack_obj($_) } $object->Inside_rearr;
    my @negative = map { $self->_pack_obj($_) } $object->Outside_rearr;

    return { description => 'rearrangements involving this gene',
	     data        => (@positive || @negative) ? { positive => \@positive,
			      negative => \@negative
	     } : undef
    };
}


#######################################
#
# The Gene Ontology widget
#   template: classes/gene/gene_ontology.tt2
#
#######################################

=head2 Gene Ontology

=cut

=head3 gene ontology

This method will return a data structure containing
curated and electronically assigned gene ontology
associations.

=over

=item PERL API

 $data = $model->gene_ontology();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/gene_ontology

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub gene_ontology {
    my $self   = shift;
    my $object = $self->object;

    # TH: This is really opaque. What is the value used for?
    # Is it a display kludge?
    my %annotation_bases = (
        'EXP', 'p',
        'IDA', 'p',
        'IPI', 'p',
        'IMP', 'p',
        'IGI', 'p',
        'IEP', 'p',
        'ND',  'p',

        'IEA', 'x',
        'ISS', 'x',
        'ISO', 'x',
        'ISA', 'x',
        'ISM', 'x',
        'IGC', 'x',
        'RCA', 'x',
        'IC',  'x'
    );

    my %data;
    foreach my $go_term ( $object->GO_term ) {
        foreach my $code ( $go_term->col ) {
            my ( $evidence_code, $method, $detail ) = $code->row;
            my $display_method = $self->_go_method_detail( $method, $detail );

            my $facet = $go_term->Type;
            $facet =~ s/_/ /g if $facet;

            my $annotation_basis = $annotation_bases{$evidence_code};
            $display_method =~ m/.*_(.*)/;    # Strip off the spam-dexer.

            push @{ $data{$facet} }, {
                method        => $1,
                evidence_code => "$evidence_code",
                term          => $self->_pack_obj($go_term),
            };
        }
    }

    return {
        description => 'gene ontology assocations',
        data        => %data ? \%data : undef,
    };
}



#######################################
#
# The History Widget
#    template: shared/widgets/history.tt2
#
#######################################

=head2 History

=cut

=head3 history

This method returns a data structure containing the 
curatorial history of the gene.

=over

=item PERL API

 $data = $model->history();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/history

B<Response example>

=cut

sub history {
    my $self   = shift;
    my $object = $self->object;
    my @data;

    foreach my $history ( $object->History ) {
        my $type = $history;
        $type =~ s/_ / /g;

        my @versions = $history->col;
        foreach my $version (@versions) {

            #  next unless $history eq 'Version_change';    # View Logic
            my ($vers,   $date,   $curator, $event,
                $action, $remark, $gene,    $person
            );
            if ( $history eq 'Version_change' ) {
                ( $vers, $date, $curator, $event, $action, $remark )
                    = $version->row;

                # For some cases, the remark is actually a gene object
                if (   $action eq 'Merged_into'
                    || $action eq 'Acquires_merge'
                    || $action eq 'Split_from'
                    || $action eq 'Split_into' )
                {
                    $gene   = $remark;
                    $remark = undef;
                }
            }
            else {
                ($gene) = $version->row;
            }

            push @data, {
                history => $history && "$history",
                version => $version && "$version",
                type    => $type && "$type",
                date    => $date && "$date",
                action  => $action && "$action",
                remark  => $remark && "$remark",
                gene    => $self->_pack_obj($gene),
                curator => $self->_pack_obj($curator),
            };
        }
    }

    return {
        description => 'the curatorial history of the gene',
        data        => @data ? \@data : undef
    };
}




#######################################
#
# The Homology Widget
#   template: classes/gene/homology.tt2
#
#######################################

=head2 Homology

=cut

# sub best_blastp_matches {}
# Supplied by Role; POD will automatically be inserted here.
# << include best_blastp_matches >>

=head3 nematode_orthologs

This method returns a data structure containing the 
orthologs of this gene to other nematodes housed
at WormBase.

=over

=item PERL API

 $data = $model->nematode_orthologs();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/nematode_orthologs

B<Response example>

=cut

sub nematode_orthologs {
    my $self   = shift;

    my $data = $self->_parse_homologs(
        [ $self->object->Ortholog ],
        sub {
            $_[0]->right(2) ? join('; ', map { "$_" } $_->right(2)->col) : undef;
        }
    );

    return {
        description => 'precalculated ortholog assignments for this gene',
        data        =>  @$data ? $data : undef,
    };

}

=head3 human_orthologs

This method returns a data structure containing the 
human orthologs of this gene.

=over

=item PERL API

 $data = $model->human_orthologs();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/human_orthologs

B<Response example>

=cut

has '_other_orthologs' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build__other_orthologs',
);

sub _build__other_orthologs {
    my ($self) = @_;
    return $self->_parse_homologs(
        [ $self->object->Ortholog_other ],
        sub {
            $_[0]->right ? join('; ', map { "$_" } $_[0]->right->col) : undef;
        }
    );
}

# I sure do wish we had some descriptions for human genes.
sub human_orthologs {
    my $self = shift;

    my @data = grep { $_->{ortholog}{id} =~ /ENSEMBL:ENSP\d/ } @{$self->_other_orthologs};

    return {
        description => 'human orthologs of this gene',
        data        => @data ? \@data : undef,
    };
}


=head3 other_orthologs

This method returns a data structure containing the 
orthologs of this gene to species outside of the core
nematodes housed at WormBase. See also nematode_orthologs()
and human_orthologs();

=over

=item PERL API

 $data = $model->other_orthologs();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/other_orthologs

B<Response example>

=cut

sub other_orthologs {
    my ($self) = @_;
    my $data = $self->_other_orthologs;

    return {
        description => 'orthologs of this gene to other species outside of core nematodes at WormBase',
        data        => @$data ? $data : undef,
    };
}

=head3 paralogs

This method returns a data structure containing the 
paralogs of this gene.

=over

=item PERL API

 $data = $model->paralogs();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/paralogs

B<Response example>

=cut

sub paralogs {
    my $self   = shift;

    my $data = $self->_parse_homologs(
        [ $self->object->Paralog ],
        sub {
            $_[0]->right(2) ? join('; ', map { "$_" } $_->right(2)->col) : undef;
        }
    );

    return {
        description => 'precalculated paralog assignments',
        data        =>  @$data ? $data : undef
    };
}

# Private helper method to standardize structure of homologs.
sub _parse_homologs {
    my ($self, $homologs, $method_sub) = @_;

    my @parsed;
    foreach (@$homologs) {
        my $packed_homolog = $self->_pack_obj($_);
        my $species = $packed_homolog->{taxonomy};
        my ($g, $spec) = split /_/, $species;
        push @parsed, {
            ortholog => $packed_homolog,
            method   => scalar $method_sub->($_),
            species  => {
                genus   => ucfirst $g,
                species => $spec,
            },
        };
    }

    return \@parsed;
}

=head3 human_diseases

This method returns a data structure containing disease
processes that human orthologs of this gene are thought
to participate in.

=over

=item PERL API

 $data = $model->human_diseases();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/human_diseases

B<Response example>

=cut

{ # closure for human_diseases
    my $built_hashes;
    my $gene2omim;
    my $omim2disease_desc;
    my $omim2disease_name;

    # THIS SERIOUSLY NEEDS TO BE FIXED.

    # the above is a temporary fix; at least the files will be loaded
    #   in once only... a more permanent solution would be a database, even if
    #   a simple one based on BDB or SQLite. -AD
    sub human_diseases {
        my $self = shift;

        unless ($built_hashes) {
            my $orthology_datadir = catdir($self->pre_compile->{base}, $self->ace_dsn->version, 'orthology');
            $gene2omim         ||= _build_hash(catfile($orthology_datadir, 'gene_id2omim_ids.txt'));
            $omim2disease_desc ||= _build_hash(catfile($orthology_datadir, 'omim_id2disease_desc.txt'));
            $omim2disease_name ||= _build_hash(catfile($orthology_datadir, 'omim_id2disease_name.txt'));
            $built_hashes = 1;
        }

        my @data_pack = map {
            omim_id 	=> $_,
            disease 	=> $omim2disease_name->{$_},
            description => $omim2disease_desc->{$_},
        }, split /%/, ($gene2omim->{$self->object} || ''); # note the comma for map!

        return {
            data        => @data_pack ? \@data_pack : undef,
            description => 'Diseases related to the gene',
        };
    }

}

=head3 protein_domains

This method returns a data structure containing the 
protein domains contained in this gene.

=over

=item PERL API

 $data = $model->protein_domains();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/protein_domains

B<Response example>

=cut

sub protein_domains {
    my $self = shift;

    my %unique_motifs;
    for my $protein ( @{ $self->_all_proteins } ) {
        for my $motif ($protein->Motif_homol) {
            if (my $title = $motif->Title) {
                $unique_motifs{$title} ||= $self->_pack_obj($motif);
            }
        }
    }

    return {
        description => "protein domains of the gene",
        data        => %unique_motifs ? \%unique_motifs : undef,
    };
}


=head3 treefam

This method returns a data structure containing the 
link outs to the Treefam resource.

=over

=item PERL API

 $data = $model->treefam();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/treefam

B<Response example>

=cut

sub treefam {
    my $self   = shift;
    my $object = $self->object;
    
    my @data;
    foreach (@{$self->_all_proteins}) {
	my $treefam = $self->_fetch_protein_ids($_,'treefam');
	# Ignore proteins that lack a Treefam ID
	next unless $treefam;
	push @data, "$treefam";
    }			
    
    return { description => 'data and IDs related to rendering Treefam trees',
	     data        => @data ? \@data : undef,
    };
}




#######################################
#
# The Interactions Widget
#   template: classes/gene/interactions.tt2
#
#######################################

=head2 Interactions

=cut

=head3 interactions

This method returns a data structure containing the 
a data table of gene and protein interactions. Ask us
to increase the granularity of this method!

=over

=item PERL API

 $data = $model->interactions();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/interactions

B<Response example>

=cut

sub interactions {
    my $self   = shift;
    my $object = $self->object;

    my @data;
    foreach my $interaction ( $object->Interaction ) {
        my $type = $interaction->Interaction_type;

        # Filter low confidence predicted interactions.
        next
            if ($interaction->Log_likelihood_score || 1000) >= 1.5
                && $type =~ /predicted/; # what happens when no data?

        my ( $effector, $effected, $direction );

        my @non_directional = eval { $type->Non_directional->col };
        if (@non_directional) {
            ( $effector, $effected ) = @non_directional;    # WBGenes
            $direction = 'non-directional';
        }
        else {
            $effector  = $type->Effector->right if $type->Effector;
            $effected  = $type->Effected->right;
            $direction = 'Effector->Effected';
        }

        my $phenotype = $type->Interaction_phenotype;

        push @data,
            {
            interaction => $self->_pack_obj($interaction),
            type        => "$type",
            effector    => $self->_pack_obj($effector),
            effected    => $self->_pack_obj($effected),
            direction   => $direction,
            phenotype   => $self->_pack_obj($phenotype)
            };
    }
    return {
        description => 'genetic and predicted interactions',
        data        => \@data
    };
}



#######################################
#
# The Location Widget
#
#######################################

=head2 Location

=cut

# sub genomic_position { }
# Supplied by Role; POD will automatically be inserted here.
# << include genomic_position >>

sub _build_genomic_position {
    my ($self) = @_;
    my @pos = $self->_genomic_position([ $self->_longest_segment || () ]);
    return {
        description => 'The genomic location of the sequence',
        data        => @pos ? \@pos : undef,
    };
}

# sub genetic_position { }
# Supplied by Role; POD will automatically be inserted here.
# << include genetic_position >>

# sub genomic_image { }
# Supplied by Role; POD will automatically be inserted here.
# << include genomic_image >>


#######################################
#
# The Phenotype Widget
#
#######################################

=head2 Phenotype

=cut

sub phenotype {
    my $self = shift;

    return {
        description => 'The Phenotype summary of the gene',
        data        => $self->_phenotypes,
	};
}

sub rnai {
    my $self = shift;

    my $data;

    my $rnai_results = $self->_rnai_results;
    my (@rnai_w_pheno, @rnai_wo_pheno);

    while (my ($rnai, $rnai_details) = each %{$rnai_results}) {
        if ($rnai_details->{phenotypes_observed}
            and %{$rnai_details->{phenotypes_observed}}) {
            push @{$data->{rnai_with_pheno}}, $rnai;
        }
        if ($rnai_details->{phenotypes_not_observed}
            and %{$rnai_details->{phenotypes_not_observed}}) {
            push @{$data->{rnai_without_pheno}}, $rnai;
        }
    }

    # $data is autovivified when accessed above by push
    $data->{rnai_results} = $rnai_results if ref $data;

    return {
        description => 'The RNAi summary of the gene',
        data        => $data,
    };
}

#######################################
#
# The Reagents Widget
#
#######################################

=head2 Reagents

=cut

=head3 antibodies

This method will return a data structure containing
antibodies generated against products of the gene.

=over

=item PERL API

 $data = $model->antibodies();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/antibodies

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub antibodies {
  my $self   = shift;
  my $object = $self->object;

  my @data;
  foreach ($object->Antibody) {
      my $summary = $_->Summary;
      push @data, { antibody   => $self->_pack_obj($_),
		    summary    => "$summary",
		    laboratory => $_->Location ? $self->_pack_obj($_->Location) : "" };
  }

  return {  description =>  "antibodies generated against protein products or gene fusions",
	    data        =>  @data ? \@data : undef };
}



=head3 matching_cdnas

This method will return a data structure containing
a list of cDNAs mapped to the gene.

=over

=item PERL API

 $data = $model->matching_cdnas();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/matching_cdnas

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub matching_cdnas {
    my $self     = shift;
    my $object = $self->object;
    my %unique;
    my @mcdnas = map {$self->_pack_obj($_)} grep {!$unique{$_}++} map {$_->Matching_cDNA} $object->Corresponding_CDS;
    return { description => 'cDNAs matching this gene',
	     data        => \@mcdnas };
}



=head3 microarray_probes

This method will return a data structure containing
microarray probes that map to the gene.

=over

=item PERL API

 $data = $model->microarray_probes();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/microarray_probes

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub microarray_probes {
    my $self   = shift;
    my $object = $self->object;

    my %seen;

    my @oligos = grep { !$seen{$_}++ }
        grep { $_->Type and $_->Type =~ /microarray_probe/ }
        map { $_->Corresponding_oligo_set } $object->Corresponding_CDS
            if ( $object->Corresponding_CDS );
    my @stash;
    foreach (@oligos) {
        my $comment
            = ( $_->Type =~ /GSC/ )
            ? 'GSC'
            : ( $_->Type =~ /Agilent/ ? 'Agilent' : 'Affymetrix' );
        push @stash, $self->_pack_obj( $_, "$_ [$comment]" );
    }

    return {
        description => "microarray probes",
        data        => @stash ? \@stash : undef,
    };
}

=head3 orfeome_primers

This method will return a data structure containing
ORFeome primers flanking the gene.

=over

=item PERL API

 $data = $model->orfeome_primers();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/orfeome_primers

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub orfeome_primers {
    my $self   = shift;
    my $object = $self->object;
    my @segments = $self->_segments ? @{$self->_segments} : undef ;
    my @ost = map { $self->_pack_obj($_)} map {$_->info} map { $_->features('alignment:BLAT_OST_BEST','PCR_product:Orfeome') } @segments if ($object->Corresponding_CDS || $object->Corresponding_Pseudogene);
    
    return { description =>  "ORFeome Project primers and sequences",
	     data        =>  @ost ? \@ost : undef };
}


=head3 primer_pairs

This method will return a data structure containing
other names that have also been used to refer to the
gene.

=over

=item PERL API

 $data = $model->primer_pairs();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/primer_pairs

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub primer_pairs {
    my $self   = shift;
    my $object = $self->object;
    
    return unless @{$self->sequences};
    
    my @segments = @{$self->_segments};
    my @primer_pairs =  
	map {$self->_pack_obj($_)} 
    map {$_->info} 
    map { $_->features('PCR_product:GenePair_STS','structural:PCR_product') } @segments;
    
    return { description =>  "Primer pairs",
	     data        =>  @primer_pairs ? \@primer_pairs : undef };
}

=head3 sage_tags

This method will return a data structure containing
Serial Analysis of Gene Expresion (SAGE) tags
that map to the gene.

=over

=item PERL API

 $data = $model->sage_tags();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/sage_tags

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub sage_tags {
    my $self   = shift;
    my $object = $self->object;
    
    my @sage_tags = map {$self->_pack_obj($_)} $object->Sage_tag;
    
    return {  description =>  "SAGE tags identified",
	      data        =>  @sage_tags ? \@sage_tags : undef
    };
}


=head3 transgenes

This method will return a data structure containing
trasngenes driven by the gene.

=over

=item PERL API

 $data = $model->transgenes();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/transgenes

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub transgenes {
    my $self   = shift;
    my $object = $self->object;
    
    my @data; 
    foreach ($object->Drives_transgene) {
	my $summary = $_->Summary;
	push @data, { transgene  => $self->_pack_obj($_),
		      laboratory => eval {$_->Location} ? $self->_pack_obj($_->Location) : '',
		      summary    => "$summary",
	};
    }
    
    return {
	description => 'transgenes expressed by this gene',
	data        => @data ? \@data : undef };    
}

=head3 transgene_products

This method will return a data structure containing
trasngenes that express this gene.

=over

=item PERL API

 $data = $model->transgene_products();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID (eg WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/transgene_products

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub transgene_products {
    my $self   = shift;
    my $object = $self->object;

    my @data; 
    foreach ($object->Transgene_product) {
	my $summary = $_->Summary;
	push @data, { transgene  => $self->_pack_obj($_),
		      laboratory => eval {$_->Location} ? $self->_pack_obj($_->Location) : '',
		      summary    => "$summary",
	};
    }
    
    return {
	description => 'transgenes that express this gene',
	data        => @data ? \@data : undef };    
}

#######################################
#
# The Regulation Widget
#   template: classes/gene/regulation.tt2
#
#######################################

=head2 Regulation

=cut

=head3 regulation_on_expression_level

This method returns a data structure containing the 
a data table describing the regulation on expression
level.

=over

=item PERL API

 $data = $model->regulation_on_expression_level();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A gene ID (WBGene00006763)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene000066763/regulation_on_expression_level

B<Response example>

=cut

sub regulation_on_expression_level {
    my $self   = shift;
    my $object = $self->object;
    my $datapack = {
        description => 'Regulation on expression level',
        data        => undef,
    };
    return $datapack unless ($object->Gene_regulation);

    my @stash;

    # Explore the relationship in both directions.
    foreach my $tag (qw/Trans_regulator Trans_target/) {
        my $join = ($tag eq 'Trans_regulator') ? 'regulated by' : 'regulates';
        if (my @gene_reg = $object->$tag(-filled=>1)) {
            foreach my $gene_reg (@gene_reg) {
                my ($string,$target);
                if ($tag eq 'Trans_regulator') {
                    $target = $gene_reg->Trans_regulated_gene(-filled=>1)
                    || $gene_reg->Trans_regulated_seq(-filled=>1)
                    || $gene_reg->Other_regulated(-filled=>1);
                } else {
                    $target = $gene_reg->Trans_regulator_gene(-filled=>1)
                    || $gene_reg->Trans_regulator_seq(-filled=>1)
                    || $gene_reg->Other_regulator(-filled=>1);
                }
                # What is the nature of the regulation?
                # If Positive_regulate and Negative_regulate are present
                # in the same gene object, then it means the localization is changed.  Go figure.
                if ($gene_reg->Positive_regulate && $gene_reg->Negative_regulate) {
                    $string .= ($tag eq 'Trans_regulator')
                    ? 'Changes localization of '
                    : 'Localization changed by ';
                } elsif ($gene_reg->Result
                         and $gene_reg->Result eq 'Does_not_regulate') {
                    $string .= ($tag eq 'Trans_regulator')
                    ? 'Does not regulate '
                    : 'Not regulated by ';
                } elsif ($gene_reg->Positive_regulate) {
                    $string .= ($tag eq 'Trans_regulator')
                    ? 'Positively regulates '
                    : 'Positively regulated by ';
                } elsif ($gene_reg->Negative_regulate) {
                    $string .= ($tag eq 'Trans_regulator')
                    ? 'Negatively regulates '
                    : 'Negatively regulated by ';
                }

                # _pack_obj may already take care of this:
                my $common_name = $self->_public_name($target);
                push @stash, {
                    string          => $string,
                    target          => $self->_pack_obj($target, $common_name),
                    gene_regulation => $self->_pack_obj($gene_reg)
                };
            }
        }
    }

    $datapack->{data} = \@stash if @stash;
    return $datapack;
}

#######################################
#
# The References Widget
#
#######################################

=head2 References

=cut

# sub references {}
# Supplied by Role; POD will automatically be inserted here.
# << include references >>

#######################################
#
# The Sequences Widget
#
#######################################

=head2 Sequences

=cut

=head3 gene_models

This method will return an extensive data structure containing
gene models for the gene.

=over

=item PERL API

 $data = $model->gene_models();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

a WBGene ID

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/gene/WBGene00006763/gene_models

B<Response example>

<div class="response-example"></div>

=back

=cut 

sub gene_models {
    my $self   = shift;
    my $object = $self->object;
    my $seqs   = $self->sequences;

    my @rows;

    # $sequence could potentially be a Transcript, CDS, Pseudogene - but
    # I still need to fetch some details from sequence
    # Fetch a variety of information about all transcripts / CDS prior to printing
    # These will be stored using the following keys (which correspond to column headers)

    foreach my $sequence ( sort { $a cmp $b } @$seqs ) {
        my %data  = ();
        my $model = $self->_pack_obj($sequence);
        my $gff   = $self->_fetch_gff_gene($sequence) or next;
        my $cds
            = ( $sequence->class eq 'CDS' )
            ? $sequence
            : eval { $sequence->Corresponding_CDS };

        my ( $confirm, $remark, $protein, @matching_cdna );
        if ($cds) {
            $confirm
                = $cds->Prediction_status;   # with or without being confirmed
            @matching_cdna
                = $cds->Matching_cDNA;       # with or without matching_cdna
            $protein = $cds->Corresponding_protein( -fill => 1 );
        }

        # Fetch all the notes for this given sequence / CDS
        my @notes = map {"$_"} (
            eval { $cds->DB_remark }, $sequence->DB_remark,
            eval { $cds->Remark },    $sequence->Remark
        );

        # Save all the remarks for each gene model.
        # We will create unique list of footnotes in the view.
        $data{remarks} = @notes ? \@notes : undef;

        if ($confirm) {
            if ( $confirm eq 'Confirmed' ) {
                $data{status} = "confirmed by cDNA(s)";
            }
            elsif ( @matching_cdna && $confirm eq 'Partially_confirmed' ) {
                $data{status} = "partially confirmed by cDNA(s)";
            }
            elsif ( $confirm eq 'Partially_confirmed' ) {
                $data{status} = "partially confirmed";
            }
            elsif ( $cds && $cds->Method eq 'history' ) {
                $data{status} = 'historical';
            }
        }
        else {
            $data{status} = "predicted";
        }

        my $len_unspliced = $gff->length;
        my $len_spliced   = 0;

        for ( $gff->features('coding_exon') ) {

            if ( $object->Species =~ /elegans/ ) {
                next unless $_->source eq 'Coding_transcript';
            }
            else {
                next
                    unless $_->method =~ /coding_exon/
                        && $_->source eq 'Coding_transcript';
            }
            next unless $_->name eq $sequence;
            $len_spliced += $_->length;
        }

        #     Try calculating the spliced length for pseudogenes
        if ( !$len_spliced ) {
            my $flag = eval { $object->Corresponding_Pseudogene } || $cds;
            for ( $gff->features('exon:Pseudogene') ) {
                next unless ( $_->name eq $flag );
                $len_spliced += $_->length;
            }
        }
        $len_spliced ||= '-';

        $data{length_spliced}   = $len_spliced;
        $data{length_unspliced} = $len_unspliced;

        if ($protein) {
            my $peplen = $protein->Peptide(2);
            my $aa     = "$peplen aa";
            $data{length_protein} = $aa if $aa;
        }
        my $protein_desc = $self->_pack_obj($protein);
        $data{model}   = $model        if $model;
        $data{protein} = $protein_desc if $protein_desc;

        push @rows, \%data;
    }

    return {
        description => 'gene models for this gene',
        data        => @rows ? \@rows : undef
    };
}

# TH: Retired 2011.08.17; safe to delete or transmogrify to some other function.
# should we return entire sequence obj or just linking/description info? -AC
sub other_sequences {
    my $self   = shift;

    my @data = map {
        my $title = $_->Title;
        {
            sequence => $self->_pack_obj($_),
            description => $title && "$title",
        }
    } $self->object->Other_sequence;

    return {
        description => 'Other sequences associated with gene',
        data        => @data ? \@data : undef,
    };
}

#########################################
#
#   INTERNAL METHODS
#
#########################################
sub _fetch_gff_gene {
    my ($self,$transcript) = @_;

    my $trans;
    my $GFF = $self->gff_dsn() or return; # should probably log this?
    eval {$GFF->fetch_group()};
    return if $@; # should probably log this

    if ($self->object->Species =~ /briggsae/) {
        ($trans) = grep {$_->method eq 'wormbase_cds'} $GFF->fetch_group(Transcript => $transcript)
            and return $trans;
    }

    ($trans) = grep {$_->method eq 'full_transcript'} $GFF->fetch_group(Transcript => $transcript)
        and return $trans;

    # Now pseudogenes
    ($trans) = grep {$_->method eq 'pseudo'} $GFF->fetch_group(Pseudogene => $transcript)
        and return $trans;

    # RNA transcripts - this is getting out of hand
    ($trans) = $GFF->segment(Transcript => $transcript);
    return $trans;
}

# This is for GO processing
# TH: I don't understand the significance of the nomenclature.
# Oh wait, I see, it's used to force an order in the view.
# This should probably be an attribute or view configuration.
sub _go_method_detail {
    my ($self,$method,$detail) = @_;
    if ($method =~ m/Paper/){
        return 'a_Curated';
    } elsif ($detail =~ m/phenotype/i) {
        return 'b_Phenotype to GO Mapping';
    } elsif ($detail =~ m/interpro/i) {
        return 'c_Interpro to GO Mapping';
    } elsif ($detail =~ m/tmhmm/i) {
        return 'd_TMHMM to GO Mapping';
    } else {
        return 'z_No Method';
    }
}

# Fetch unique transcripts (Transcripts or Pseudogenes) for the gene
sub _fetch_transcripts { # pending deletion
    my $self = shift;
    my $object = $self->object;
    my %seen;
    my @seqs = grep { !$seen{$_}++} $object->Corresponding_transcript;
    my @cds  = $object->Corresponding_CDS;
    foreach (@cds) {
	next if defined $seen{$_};
	my @transcripts = grep {!$seen{$_}++} $_->Corresponding_transcript;
	push (@seqs,(@transcripts) ? @transcripts : $_);
    }
    @seqs = $object->Corresponding_Pseudogene unless @seqs;
    return \@seqs;
}

sub _build__segments {
    my ($self) = @_;
    my $sequences = $self->sequences;
    my @segments;
    my $dbh = $self->gff_dsn() || return \@segments;

    my $object = $self->object;
    my $species = $object->Species;

    eval {$dbh->segment()}; return \@segments if $@;

    # Yuck. Still have some species specific stuff here.

    if (@$sequences and $species =~ /briggsae/) {
        if (@segments = map {$dbh->segment(CDS => "$_")} @$sequences
            or @segments = map {$dbh->segment(Pseudogene => "$_")} @$sequences) {
            return \@segments;
        }
    }

    if (@segments = $dbh->segment(Gene => $object)
        or @segments = map {$dbh->segment(CDS => $_)} @$sequences
        or @segments = map { $dbh->segment(Pseudogene => $_) } $object->Corresponding_Pseudogene # Pseudogenes (B0399.t10)
        or @segments = map { $dbh->segment(Transcript => $_) } $object->Corresponding_Transcript # RNA transcripts (lin-4, sup-5)
    ) {
        return \@segments;
    }

    return;
}

# TODO: Logically this might reside in Model::GFF although I don't know if it is used elsewhere
# Find the longest GFF segment
sub _longest_segment {
    my ($self) = @_;
    # Not all genes are cloned and will have segments associated with them.
    my ($longest)
	= sort { $b->abs_end - $b->abs_start <=> $a->abs_end - $a->_abs_start}
    @{$self->_segments} if $self->_segments;
    return $longest;
}

sub _select_protein_description { # pending deletion
    my ($self,$seq,$protein) = @_;
    my %labels = (Pseudogene => 'Pseudogene; not attached to protein',
		  history     => 'historical prediction',
		  RNA         => 'non-coding RNA transcript',
		  Transcript  => 'non-coding RNA transcript',
	);
    my $error = $labels{eval{$seq->Method}};
    $error ||= eval { ($seq->Remark =~ /dead/i) ? 'dead/retired gene' : ''};
    my $msg = $protein ? $protein : $error;
    return $msg;
}


# I need to retain this in order to link to Treefam.
sub _fetch_protein_ids {
    my ($self,$s,$tag) = @_;
    my @dbs = $s->Database;
    foreach (@dbs) {
	return $_->right(2) if (/$tag/i);
    }
    return;
}

# TODO: This could logically be moved into a template
sub _other_notes { # pending deletion
    my ($self,$object) = @_;
    
    my @notes;
    if ($object->Corresponding_Pseudogene) {
	push (@notes,'This gene is thought to be a pseudogene');
    }
    
    if ($object->CGC_name || $object->Other_name) {
	if (my @contained_in = $object->In_cluster) {
#####      my $cluster = join ' ',map{a({-href=>Url('gene'=>"name=$_")},$_)} @contained_in;
	    my $cluster = join(' ',@contained_in);
	    push @notes,"This gene is contained in gene cluster $cluster.\n";
	}
	
#####    push @notes,map { GetEvidence(-obj=>$_,-dont_link=>1) } $object->Remark if $object->Remark;
	push @notes,$object->Remark if $object->Remark;
    }
    
    # Add a brief remark for Transposon CDS entries
    push @notes,
    'This gene is believed to represent the remnant of a transposon which is no longer functional'
	if (eval {$object->Corresponding_CDS->Method eq 'Transposon_CDS'});
    
    foreach (@notes) {
	$_ = ucfirst($_);
	$_ .= '.' unless /\.$/;
    }
    return \@notes;
}

sub parse_year { # pending deletion
    my $date = shift;
    $date =~ /.*(\d\d\d\d).*/;
    my $year = $1 || $date;
    return $year;
}


sub _pattern_thumbnail {
    my ($self,$ep) = @_;
    return '' unless $self->_is_cached($ep->name);
    my $terms = join ', ', map {$_->Term} $ep->Anatomy_term;
    $terms ||= "No adult terms in the database";
    return ([$ep,$terms]);
}

# Meh. This is a view component and doesn't belong here.
sub _is_cached {
    my ($self,$ep) = @_;
    my $WORMVIEW_IMG = '/usr/local/wormbase/html/images/expression/assembled/';
    return -e $WORMVIEW_IMG . "$ep.png";
}



sub _y2h_data { # pending deletion
    my ($self,$object,$limit,$c) = @_;
    my %tags = ('YH_bait'   => 'Target_overlapping_CDS',
		'YH_target' => 'Bait_overlapping_CDS');
    
    my %results;
    foreach my $tag (keys %tags) {
	if (my @data = $object->$tag) {
	    
# Map baits/targets to CDSs
	    my $subtag = $tags{$tag};
	    my %seen = ();
	    foreach (@data) {
		my @cds = $_->$subtag;
		
		unless (@cds) {
		    my $try_again = ($subtag eq 'Bait_overlapping_CDS') ? 'Target_overlapping_CDS' : 'Bait_overlapping_CDS';
		    @cds = $_->$try_again;
		}
		
		unless (@cds) {
		    my $try_again = ($subtag eq 'Bait_overlapping_CDS') ? 'Bait_overlapping_gene' : 'Target_overlapping_gene';
		    my $new_gene = $_->$try_again;
		    @cds = $new_gene->Corresponding_CDS if $new_gene;
		}
		
		foreach my $cds (@cds) {
		    push @{$seen{$cds}},$_;
		}    
	    }
	    
	    my $count = 0;
	    for my $cds (keys %seen){
		my ($y2h_ref,$count);
		my $str = "See: ";
		for my $y2h (@{$seen{$cds}}) {
		    $count++;
		    # If we are limiting for the main page, append a link to "more"
		    last if ($limit && $count > $limit);
#	  $str    .= " " . $c->object2link($y2h);
		    $str    .= " " . $y2h;
		    $y2h_ref  = $y2h->Reference;
		}
		if ($limit && $count > $limit) {
#	  my $link = DisplayMoreLink(\@data,'y2h',undef,'more',1);
#	  $link =~ s/[\[\]]//g;
#	  $str .= " $link";
		}
		my $dbh = $self->service('acedb');
		my $k_cds = $dbh->fetch(CDS => $cds);
		#	push @{$results{$tag}}, [$c->object2link($k_cds) . " [" . $str ."]", $y2h_ref];
		push @{$results{$tag}}, [$k_cds . " [" . $str ."]", $y2h_ref];
	    }
	}
    }
    return (\@{$results{'YH_bait'}},\@{$results{'YH_target'}});
}



# This is one big ugly hack job
sub _go_evidence_code { # pending deletion
    my ($self,$term) = @_;
    my @type      = $term->col;
    my @evidence  = $term->right->col if $term->right;
    my @results;
    foreach my $type (@type) {
	my $evidence = '';
	
	for my $ev (@evidence) {
	    my $desc;
	    my (@supporting_data) = $ev->col;
	    
	    # For IMP, this is semi-formatted text remark
	    if ($type eq 'IMP' && $type->right eq 'Inferred_automatically') {
		my (%phenes,%rnai);
		foreach (@supporting_data) {
		    my @row;
		    $_ =~ /(.*) \(WBPhenotype(.*)\|WBRNAi(.*)\)/;
		    my ($phene,$wb_phene,$wb_rnai) = ($1,$2,$3);
		    $rnai{$wb_rnai}++ if $wb_rnai;
		    $phenes{$wb_phene}++ if $wb_phene;
		}
#	$evidence .= 'via Phenotype: '
#	  #		  . join(', ',map { a({-href=>ObjectLink('phenotype',"WBPhenotype$_")},$_) }
#	  . join(', ',map { a({-href=>Object2URL("WBPhenotype$_",'phenotype')},$_) }
#		 
#		 keys %phenes) if keys %phenes > 0;
		
		$evidence .= 'via Phenotype: '
		    . join(', ',		 keys %phenes) if keys %phenes > 0;
		
		$evidence .= '; ' if $evidence && keys %rnai > 0;
		
#	$evidence .= 'via RNAi: '
#	  . join(', ',map { a({-href=>Object2URL("WBRNAi$_",'rnai')},$_) } 
#		 keys %rnai) if keys %rnai > 0;
		$evidence .= 'via RNAi: '
		    . join(', ', keys %rnai) if keys %rnai > 0;
		
		next;
	    }
	    
	    my @seen;
	    
	    foreach (@supporting_data) {
		if ($_->class eq 'Paper') {  # a paper
#	  push @seen,ObjectLink($_,build_citation(-paper=>$_,-format=>'short'));
		    
		    push @seen,$_;
		} elsif ($_->class eq 'Person') {
		    #		  push @seen,ObjectLink($_,$_->Standard_name);
		    next;
		} elsif ($_->class eq 'Text' && $ev =~ /Protein/) {  # a protein
#	  push @seen,a({-href=>sprintf(Configuration->Protein_links->{NCBI},$_),-target=>'_blank'},$_);
		} else {
#	  push @seen,ObjectLink($_);
		    push @seen,$_;
		}
	    }
	    if (@seen) {
		$evidence .= ($evidence ? ' and ' : '') . "via $desc ";
		$evidence .= join('; ',@seen); 
	    }
	}
	
	
	# Return an array of arrays, containing the go evidence code (IMP, IEA) and its source (RNAi, paper, curator, etc)
	push @results,[$type,($type eq 'IEA') ? 'via InterPro' : $evidence];
    }
    #my @proteins = $term->at('Protein_id_evidence');
    return @results;
}

sub _build_hash {
    open my $fh, '<', $_[0] or die $!;

    return { map { chomp; split /=>/, $_, 2 } <$fh> };
}

# helper method, retrieve public name from objects
sub _public_name {

    my ($self,$object) = @_;
    my $common_name;
    my $class = eval{$object->class} || "";

    if ($class =~ /gene/i) {
        $common_name =
        $object->Public_name
        || $object->CGC_name
        || $object->Molecular_name
        || eval { $object->Corresponding_CDS->Corresponding_protein }
        || $object;
    }
    elsif ($class =~ /protein/i) {
        $common_name =
        $object->Gene_name
        || eval { $object->Corresponding_CDS->Corresponding_protein }
        ||$object;
    }
    else {
        $common_name = $object;
    }

    my $data = $common_name;
    return "$data";


}

#######################################
#
# OBSOLETE METHODS?
#
#######################################

# Fetch all proteins associated with a gene.
## NB: figure out the naming convention for proteins

# NOTE: this method is not used
# sub proteins {
#     my $self   = shift;
#     my $object = $self->object;
#     my $desc = 'proteins related to gene';

#     my @cds    = $object->Corresponding_CDS;
#     my @proteins  = map { $_->Corresponding_protein } @cds;
#     @proteins = map {$self->_pack_obj($_, $self->public_name($_, $_->class))} @proteins;

#     return { description => 'proteins encoded by this gene',
# 	     data        => \@proteins };
# }


# # Fetch all CDSs associated with a gene.
# ## figure out naming convention for CDs

# # NOTE: this method is not used
# sub cds {
#     my $self   = shift;
#     my $object = $self->object;
#     my @cds    = $object->Corresponding_CDS;
#     my $data_pack = $self->basic_package(\@cds);

#     return { description => 'CDSs encoded by this gene',
# 	     data        => $data_pack };
# }



# # Fetch Homology Group Objects for this gene.
# # Each is associated with a protein and we should probably
# # retain that relationship

# # NOTE: this method is not used
# # TH: NOT YET CLEANED UP
# sub kogs {
#     my $self   = shift;
#     my $object = $self->object;
#     my @cds    = $object->Corresponding_CDS;
#     my %data;
#     my %data_pack;

#     if (@cds) {
# 	my @proteins  = map {$_->Corresponding_protein(-fill=>1)} @cds;
# 	if (@proteins) {
# 	    my %seen;
# 	    my @kogs = grep {$_->Group_type ne 'InParanoid_group' } grep {!$seen{$_}++}
# 	         map {$_->Homology_group} @proteins;
# 	    if (@kogs) {

# 	    	$data_pack{$object} = \@kogs;
# 			$data{'data'} = \%data_pack;

# 	    } else {

# 	    	$data_pack{$object} = 1;

# 	    }
# 	}
#     } else {
# 		$data_pack{$object} = 1;
#     }

#     $data{'description'} = "KOGs related to gene";
#  	return \%data;
# }

__PACKAGE__->meta->make_immutable;

1;
