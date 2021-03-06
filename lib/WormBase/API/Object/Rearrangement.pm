package WormBase::API::Object::Rearrangement;
use Moose;

with 'WormBase::API::Role::Object';
extends 'WormBase::API::Object';

=pod 

=head1 NAME

WormBase::API::Object::Rearrangement

=head1 SYNPOSIS

Model for the Ace ?Rearrangement class.

=head1 URL

http://wormbase.org/resources/rearrangement

=cut


#######################################
#
# CLASS METHODS
#
#######################################

=head1 CLASS LEVEL METHODS/URIs

=cut


#######################################
#
# INSTANCE METHODS
#
#######################################

=head1 INSTANCE LEVEL METHODS/URIs

=cut


#######################################
#
# The Overview Widget
#
#######################################

=head2 Overview

=cut

# sub name { }
# Supplied by Role; POD will automatically be inserted here.
# << include name >>

=head3 type

This method returns a data structure containing the 
type of the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->type();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/type

B<Response example>

<div class="response-example"></div>

=back

=cut

sub type {
    my $self = shift;
    my @types = map {
	my $right;
	if ($right = $_->right) {"$_:$right"}
	else {"$_"}
    } $self->object->Type;

    return {
        description => 'the type of rearrangement',
        data        => @types ? \@types : undef,
    };
}

=head3 mapping_data

This method returns a data structure containing the 
mapping_data of the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->mapping_data();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/mapping_data

B<Response example>

<div class="response-example"></div>

=back

=cut

sub mapping_data {
    my $self = shift;
    my $object = $self->object;
    my @data;

    foreach my $info ($object->Pos_neg_data) {
	my $genotype = $info->Genotype;
	my $results = $info->Results;
	my @remarks = map {
	    my $evidence = $self->_get_evidence($_);
	    $evidence ? {text => "$_", evidence => $evidence} : "$_"
	} $info->Remark;
	my @authors = map {$self->_pack_obj($_)} $info->Mapper;
	my %hash = (
	    type => $info->Calculation eq 'Positive' ? '+' : '-',
	    author => @authors ? \@authors : undef,
	    genotype => $genotype && "$genotype",
	    remark => @remarks ? \@remarks : undef,
	    results => $results && "$results",
	);
	foreach my $item ('Item_1', 'Item_2') {
	    my $class = $info->$item;
	    next unless $class;

	    my $obj = $class->right;
	    next if ("$obj" eq "$object");
	    $hash{name} = $self->_pack_obj($obj);
	    $hash{class} = $class =~ /(.*)_\d/ ? "$1" : undef;
	    $hash{position} = $self->_get_position($hash{class}, $obj);
	}

	push @data, \%hash;
    }

    return {
        description => 'the mapping data of the rearrangement',
        data        => @data ? \@data : undef,
    };
}

=head3 positive

This method returns a data structure containing the 
genes/clones/rearrangements/loci inside the rearrangement.

=over

=item PERL API

 $data = $model->positive();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/positive

B<Response example>

<div class="response-example"></div>

=back

=cut

sub positive {
    my $self = shift;

    return { description => 'Covered by rearrangement',
	     data => $self->_inside_out('Positive'),
    };
}

=head3 negative

This method returns a data structure containing the 
genes/clones/rearrangements/loci outside the rearrangement.

=over

=item PERL API

 $data = $model->negative();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/negative

B<Response example>

<div class="response-example"></div>

=back

=cut

sub negative {
    my $self = shift;

    return { description => 'Not covered by rearrangement',
	     data => $self->_inside_out('Negative'),
    };
}

sub _inside_out {
    my ($self, $tag) = @_;
    my $object = $self->object;
    my %data;

    foreach my $type ($object->$tag) {
	my @list = map {$self->_pack_obj($_)} $object->$type;

	if ($type =~ /(Gene|Clone)_(.*)/) { $type = $1 . 's ' . $2 } #pluralize
	elsif ($type =~ /Locus_(.*)/) { $type = 'Loci ' . $1; }
	elsif ($type =~ /Rearr_(.*)/ ) { $type = 'Rearrange ' . $1; }
	
	$data{$type} = @list ? \@list : undef;
    }

    return %data ? \%data : undef;

}

=head3 display

This method returns a data structure containing the 
rearrangements hidden by this rearrangement.

=over

=item PERL API

 $data = $model->display();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/display

B<Response example>

<div class="response-example"></div>

=back

=cut

sub display {
    my $self = shift;
    my $object = $self->object;
    my %data;

    my @hides = map {$self->_pack_obj($_)} $object->Hides;
    my $hidden = $self->_pack_obj($object->Hide_under);
    $data{'Hides'} = \@hides if @hides;
    $data{'Hidden Under'} = $hidden if $hidden;

    return { description => 'Rearrangements Hiding/Hidden by this rearrangement',
	     data => %data ? \%data : undef,
    };
}

=head3 strains

This method returns a data structure containing the 
strains associated with the rearrangement.

=over

=item PERL API

 $data = $model->strains();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/strains

B<Response example>

<div class="response-example"></div>

=back

=cut

sub strains {
    my $self = shift;
    my $object = $self->object;
    my @data;

    foreach my $strain ($object->Strain){
	push @data, {
	    strain => $self->_pack_obj($strain),
	    info => {genotype => $self->_get_genotype($strain)},
	}
    }

    return { description => 'Strains associated with the Rearrangement',
	     data => @data ? \@data : undef,
    };
}

=head3 reference_strain

This method returns a data structure containing the 
reference strain associated with the rearrangement.

=over

=item PERL API

 $data = $model->reference_strain();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/reference_strain

B<Response example>

<div class="response-example"></div>

=back

=cut

sub reference_strain {
    my $self = shift;
    my $object = $self->object;

    my @data = map {$self->_pack_obj($_)} $object->Reference_strain;

    return { description => 'Reference strains for the Rearrangement',
	     data => @data ? \@data : undef,
    };
}

=head3 chromosome

This method returns a data structure containing the 
chromosomal information of the rearrangement.

=over

=item PERL API

 $data = $model->chromosome();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/chromosome

B<Response example>

<div class="response-example"></div>

=back

=cut

sub chromosome {
    my $self = shift;
    my $object = $self->object;
    my $str;
    my ($tag) = grep {"$_" eq 'Map'} $object->tags;
    my $map = $object->$tag if $tag;
    $str = $map ? "$map" : '';
    my ($left, $right) = $tag->col(3) if $tag;
    $left = sprintf "%.2f", $left->at if $left;
    $right = sprintf "%.2f", $right->at if $right;
    $str .= $left && $right ? ": $left to $right" : '';

    return { description => 'Reference strains for the Rearrangement',
	     data => "$str" || undef,
    };
}

#######################################
#
# The Phenotypes widget
#
####################################### 

=head2 Phenotypes

=cut

# sub phenotypes {}
# Supplied by Role; POD will automatically be inserted here.
# << include phenotypes >>

# sub phenotypes_not_observed {}
# Supplied by Role; POD will automatically be inserted here.
# << include phenotypes_not_observed >>

sub _build_phenotypes_data {
    my $self = shift;
    my $tag = shift;
    my $object = $self->object;
#     $tag = '@'.$tag;
    return [ map {
        my $desc = $_->Description;
        my $remark = $_->Remark;
        {
            phenotype   => $self->_pack_obj($_),
            evidence => { text=> $desc && "$desc", evidence => $self->_get_evidence($desc)},
        };
    } @{$self ~~ '@'.$tag} ];
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
# The Isolation Widget
#
#######################################

=head2 Isolation

=head3 author

This method returns a data structure containing the 
author associated with the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->author();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/author

B<Response example>

<div class="response-example"></div>

=back

=cut

sub author {
    my $self = shift;
    my $object = $self->object;

    my @data = map {$self->_pack_obj($_)} $object->Author;

    return { description => 'Author associated with the Rearrangement',
	     data => @data ? \@data : undef,
    };
}

=head3 mutagen

This method returns a data structure containing the 
mutagen associated with the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->mutagen();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/mutagen

B<Response example>

<div class="response-example"></div>

=back

=cut

sub mutagen {
    my $self = shift;
    my $object = $self->object;

    my $mutagen = $object->Mutagen;

    return { description => 'Mutagen associated with the Rearrangement',
	     data => $mutagen && "$mutagen",
    };
}

=head3 date

This method returns a data structure containing the 
date associated with the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->date();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/date

B<Response example>

<div class="response-example"></div>

=back

=cut

sub date {
    my $self = shift;
    my $object = $self->object;

    my $date = $object->Date;

    return { description => 'Mutagen associated with the Rearrangement',
	     data => $date && "$date",
    };
}

=head3 source

This method returns a data structure containing the 
source rearrangement for the rearrangement, if there is one.

=over

=item PERL API

 $data = $model->source();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/source

B<Response example>

<div class="response-example"></div>

=back

=cut

sub source {
    my $self = shift;
    my $object = $self->object;

    return { description => 'Source rearrangement for this rearrangement',
	     data => $self->_pack_obj($object->Source_rearrangement),
    };
}

=head3 derived

This method returns a data structure containing the 
rearrangements derived from this rearrangement.

=over

=item PERL API

 $data = $model->derived();

=item REST API

B<Request Method>

GET

B<Requires Authentication>

No

B<Parameters>

A Rearrangement (eg mnDp11)

B<Returns>

=over 4

=item *

200 OK and JSON, HTML, or XML

=item *

404 Not Found

=back

B<Request example>

curl -H content-type:application/json http://api.wormbase.org/rest/field/rearrangement/mnDp11/derived

B<Response example>

<div class="response-example"></div>

=back

=cut

sub derived {
    my $self = shift;
    my $object = $self->object;

    my @data = map {$self->_pack_obj($_)} $object->Derived_rearrangement;

    return { description => 'Rearrangements derived from this rearrangement',
	     data => @data ? \@data : undef,
    };
}

sub _build_laboratory {
    my ($self) = @_;
    my $object = $self->object;

    my @data;

    if (my $lab = $object->Location) {    
	my $label = $lab->Mail || "$lab";
	my $representative = $lab->Representative;
	my $name = $representative->Standard_name if $representative;
	push @data, {
	    laboratory => $self->_pack_obj($lab, "$label"),
	    representative => $self->_pack_obj($representative, "$name"),
	};
    }

    return {
        description => 'The location associated with this rearrangement',
        data        => @data ? \@data : undef,
    };
}

#######################################
#
# Private Methods
#
#######################################

sub _get_position {
    my ($self, $type, $obj) = @_;
    my $result;

    if ($type eq 'Gene') {
	foreach my $info ($obj->Map_info) {
	    next unless "$info" eq 'Map';
	    my @row = $info->row(1);
	    my $map = $row[0];
	    my $pos = sprintf "%.2f", $row[2];
	    my $err = sprintf "%.3f", $row[4];
	    $err = $err =~ /(.\..{3})/ ? $1 : $pos;
	    $result = "$map: $pos";
	    $result .= " +/- $err" if $err;
	}
    }

    return $result || "-";
}

__PACKAGE__->meta->make_immutable;

1;

