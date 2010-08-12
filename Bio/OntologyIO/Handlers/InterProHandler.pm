#
# BioPerl module for InterProHandler
#
# Please direct questions and support issues to <bioperl-l@bioperl.org>
#
# Cared for by Peter Dimitrov <dimitrov@gnf.org>
#
# Copyright Peter Dimitrov
# (c) Peter Dimitrov, dimitrov@gnf.org, 2003.
# (c) GNF, Genomics Institute of the Novartis Research Foundation, 2003.
#
# You may distribute this module under the same terms as perl itself.
# Refer to the Perl Artistic License (see the license accompanying this
# software package, or see http://www.perl.com/language/misc/Artistic.html)
# for the terms under which you may use, modify, and redistribute this module.
#
# THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# POD documentation - main docs before the code

=head1 NAME

Bio::OntologyIO::Handlers::InterProHandler - XML handler class for InterProParser

=head1 SYNOPSIS

 # do not use directly - used and instantiated by InterProParser

=head1 DESCRIPTION

Handles xml events generated by InterProParser when parsing InterPro
XML files.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Support

Please direct usage questions or support issues to the mailing list:

I<bioperl-l@bioperl.org>

rather than to the module maintainer directly. Many experienced and
reponsive experts will be able look at the problem and quickly
address it. Please include a thorough description of the problem
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via the
web:

  http://bugzilla.open-bio.org/

=head1 AUTHOR - Peter Dimitrov

Email dimitrov@gnf.org

=head1 CONTRIBUTORS

Juguang Xiao, juguang@tll.org.sg

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::OntologyIO::Handlers::InterProHandler;
use strict;
use Carp;
use Bio::Ontology::Ontology;
use Bio::Ontology::RelationshipType;
use Bio::Ontology::SimpleOntologyEngine;
use Bio::Annotation::Reference;
use Data::Dumper;

use base qw(Bio::Root::Root);

my ( $record_count, $processed_count, $is_a_rel, $contains_rel, $found_in_rel );

=head2 new

 Title   : new
 Usage   : $h = Bio::OntologyIO::Handlers::InterProHandler->new;
 Function: Initializes global variables
 Example :
 Returns : an InterProHandler object
 Args    :


=cut

sub new {
    my ( $class, @args ) = @_;
    my $self = $class->SUPER::new(@args);

    my ( $eng, $ont, $name, $fact ) = $self->_rearrange(
        [qw[
            ENGINE
            ONTOLOGY
            ONTOLOGY_NAME
            TERM_FACTORY
        ]],
        @args
    );

    if ( defined($ont) ) {
        $self->ontology($ont);
    } else {
        $name = "InterPro" unless $name;
        $self->ontology( Bio::Ontology::Ontology->new( -name => $name ) );
    }
    $self->ontology_engine($eng) if $eng;

    $self->term_factory($fact) if $fact;

    $is_a_rel     = Bio::Ontology::RelationshipType->get_instance("IS_A");
    $contains_rel = Bio::Ontology::RelationshipType->get_instance("CONTAINS");
    $found_in_rel = Bio::Ontology::RelationshipType->get_instance("FOUND_IN");
    $is_a_rel->ontology( $self->ontology() );
    $contains_rel->ontology( $self->ontology() );
    $found_in_rel->ontology( $self->ontology() );
    $self->_cite_skip(0);
    $self->secondary_accessions_map( {} );

    return $self;
}

=head2 ontology_engine

 Title   : ontology_engine
 Usage   : $obj->ontology_engine($newval)
 Function: Get/set ontology engine. Can be initialized only once.
 Example :
 Returns : value of ontology_engine (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub ontology_engine {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        if ( defined $self->{'ontology_engine'} ) {
            $self->throw("ontology_engine already defined");
        } else {
            $self->throw(
                ref($value) . " does not implement " . "Bio::Ontology::OntologyEngineI. Bummer." )
                unless $value->isa("Bio::Ontology::OntologyEngineI");
            $self->{'ontology_engine'} = $value;

            # don't forget to set this as the engine of the ontology, otherwise
            # those two might not point to the same object
            my $ont = $self->ontology();
            if ( $ont && $ont->can("engine") && ( !$ont->engine() ) ) {
                $ont->engine($value);
            }

            $self->debug(
                      ref($self)
                    . "::ontology_engine: registering ontology engine ("
                    . ref($value) . "):\n"
                    . $value->to_string
                    . "\n" );
        }
    }

    return $self->{'ontology_engine'};
}

=head2 ontology

 Title   : ontology
 Usage   :
 Function: Get the ontology to add the InterPro terms to.

           The value is determined automatically once ontology_engine
           has been set and if it hasn't been set before.

 Example :
 Returns : A L<Bio::Ontology::OntologyI> implementing object.
 Args    : On set, a L<Bio::Ontology::OntologyI> implementing object.

=cut

sub ontology {
    my ( $self, $ont ) = @_;

    if ( defined($ont) ) {
        $self->throw( ref($ont) . " does not implement Bio::Ontology::OntologyI" . ". Bummer." )
            unless $ont->isa("Bio::Ontology::OntologyI");
        $self->{'_ontology'} = $ont;
    }
    return $self->{'_ontology'};
}

=head2 term_factory

 Title   : term_factory
 Usage   : $obj->term_factory($newval)
 Function: Get/set the ontology term object factory
 Example :
 Returns : value of term_factory (a Bio::Factory::ObjectFactory instance)
 Args    : on set, new value (a Bio::Factory::ObjectFactory instance
           or undef, optional)


=cut

sub term_factory {
    my $self = shift;

    return $self->{'term_factory'} = shift if @_;
    return $self->{'term_factory'};
}

=head2 _cite_skip

 Title   : _cite_skip
 Usage   : $obj->_cite_skip($newval)
 Function:
 Example :
 Returns : value of _cite_skip (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _cite_skip {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_cite_skip'} = $value;
    }

    return $self->{'_cite_skip'};
}

=head2 _hash

 Title   : _hash
 Usage   : $obj->_hash($newval)
 Function:
 Example :
 Returns : value of _hash (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _hash {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_hash'} = $value;
    }

    return $self->{'_hash'};
}

=head2 _stack

 Title   : _stack
 Usage   : $obj->_stack($newval)
 Function:
 Example :
 Returns : value of _stack (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _stack {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_stack'} = $value;
    }
    return $self->{'_stack'};
}

=head2 _top

 Title   : _top
 Usage   :
 Function:
 Example :
 Returns :
 Args    :


=cut

sub _top {
    my ( $self, $_stack ) = @_;
    my @stack = @{$_stack};

    return ( @stack >= 1 ) ? $stack[ @stack - 1 ] : undef;
}

=head2 _term

 Title   : _term
 Usage   : $obj->_term($newval)
 Function: Get/set method for the term currently processed.
 Example :
 Returns : value of term (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _term {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_term'} = $value;
    }

    return $self->{'_term'};
}

=head2 _clear_term

 Title   : _clear_term
 Usage   :
 Function: Removes the current term from the handler
 Example :
 Returns :
 Args    :


=cut

sub _clear_term {
    my ($self) = @_;

    delete $self->{'_term'};
}

=head2 _names

 Title   : _names
 Usage   : $obj->_names($newval)
 Function:
 Example :
 Returns : value of _names (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _names {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_names'} = $value;
    }

    return $self->{'_names'};
}

=head2 _create_relationship

 Title   : _create_relationship
 Usage   :
 Function: Helper function. Adds relationships to one of the relationship stores.
 Example :
 Returns :
 Args    :


=cut

sub _create_relationship {
    my ( $self, $ref_id, $rel_type_term ) = @_;
    my $ont       = $self->ontology();
    my $fact      = $self->term_factory();
    my $term_temp = ( $ont->engine->get_term_by_identifier($ref_id) )[0];

    my $rel = Bio::Ontology::Relationship->new( -predicate_term => $rel_type_term );

    if ( !defined $term_temp ) {
        $term_temp =
            $ont->engine->add_term(
            $fact->create_object( -InterPro_id => $ref_id, -name => $ref_id, -ontology => $ont ) );
        $ont->engine->mark_uninstantiated($term_temp);
    }
    my $rel_type_name = $self->_top( $self->_names );

    # commented out; assumption that terms need to be inverted is not correct -
    # cjfields
    
    #if ( $rel_type_name eq 'parent_list' || $rel_type_name eq 'found_in' ) {
            #$rel->object_term($term_temp);
            #$rel->subject_term( $self->_term );
    #} else {
        $rel->object_term( $self->_term );
        $rel->subject_term($term_temp);
    #}
    $rel->ontology($ont);
    $ont->add_relationship($rel);
}

=head2 start_element

 Title   : start_element
 Usage   :
 Function: This is a method that is derived from XML::SAX::Base and
           has to be overridden for processing start of xml element
           events. Used internally only.

 Example :
 Returns :
 Args    :


=cut

sub start_element {
    my ( $self, $element ) = @_;
    my $ont  = $self->ontology();
    my $fact = $self->term_factory();

    if ( $element->{Name} eq 'interprodb' ) {
        $ont->add_term(
            $fact->create_object(
                -identifier => "Active_site",
                -name       => "Active Site"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Conserved_site",
                -name       => "Conserved Site"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Binding_site",
                -name       => "Binding Site"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Family",
                -name       => "Family"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Domain",
                -name       => "Domain"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Repeat",
                -name       => "Repeat"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "PTM",
                -name       => "post-translational modification"
            )
        );
        $ont->add_term(
            $fact->create_object(
                -identifier => "Region",
                -name       => "Region"
            )
        );
    } elsif ( $element->{Name} eq 'interpro' ) {
        my %record_args = %{ $element->{Attributes} };
        my $id          = $record_args{"id"};

        # this sets the current term
        my $term   = ( $ont->engine->get_term_by_identifier($id) )[0] || 
            $fact->create_object( -InterPro_id => $id, -name => $id );
        $self->_term($term);

        $term->ontology($ont);
        $term->short_name( $record_args{"short_name"} );
        $term->protein_count( $record_args{"protein_count"} );
        $self->_increment_record_count();
        $self->_stack( [ { interpro => undef } ] );
        $self->_names( ["interpro"] );

        ## Adding a relationship between the newly created InterPro term
        ## and the term describing its type

        my $rel = Bio::Ontology::Relationship->new( -predicate_term => $is_a_rel );
        my ($object_term) = $ont->find_terms( -identifier => $record_args{"type"} )
            or $self->throw(
"when processing interpro ID '$id', no term found for interpro type '$record_args{type}'"
            );
        $rel->object_term($object_term);
        $rel->subject_term( $self->_term );
        $rel->ontology($ont);
        $ont->add_relationship($rel);
        $ont->add_term($term);
    } elsif ( defined $self->_stack ) {
        my %hash = ();

        if ( keys %{ $element->{Attributes} } > 0 ) {
            foreach my $key ( keys %{ $element->{Attributes} } ) {
                $hash{$key} = $element->{Attributes}->{$key};
            }
        }
        push @{ $self->_stack }, \%hash;
        if ( $element->{Name} eq 'rel_ref' ) {
            my $ref_id = $element->{Attributes}->{"ipr_ref"};
            my $parent = $self->_top( $self->_names );

            if ( $parent eq 'parent_list' || $parent eq 'child_list' ) {
                $self->_create_relationship( $ref_id, $is_a_rel );
            }
            if ( $parent eq 'contains' ) {
                $self->_create_relationship( $ref_id, $contains_rel );
            }
            if ( $parent eq 'found_in' ) {
                $self->_create_relationship( $ref_id, $found_in_rel );
            }
        } elsif ( $element->{Name} eq 'abstract' ) {
            $self->_cite_skip(1);
        }
        push @{ $self->_names }, $element->{Name};
    }

}

=head2 _char_storage

 Title   : _char_storage
 Usage   : $obj->_char_storage($newval)
 Function:
 Example :
 Returns : value of _char_storage (a scalar)
 Args    : new value (a scalar, optional)


=cut

sub _char_storage {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'_char_storage'} = $value;
    }

    return $self->{'_char_storage'};
}

=head2 characters

 Title   : characters
 Usage   :
 Function: This is a method that is derived from XML::SAX::Base and has to be overridden for processing xml characters events. Used internally only.
 Example :
 Returns :
 Args    :


=cut

sub characters {
    my ( $self, $characters ) = @_;
    my $text = $characters->{Data};

    chomp $text;
    $text =~ s/^(\s+)//;
    $self->{_char_storage} .= $text;

}

=head2 end_element

 Title   : end_element
 Usage   :
 Function: This is a method that is derived from XML::SAX::Base and has to be overridden for processing end of xml element events. Used internally only.
 Example :
 Returns :
 Args    :


=cut

sub end_element {
    my ( $self, $element ) = @_;

    if ( $element->{Name} eq 'interprodb' ) {
        $self->debug(
            "Interpro DB Parser Finished: $record_count read, $processed_count processed\n");
    } elsif ( $element->{Name} eq 'interpro' ) {
        $self->_clear_term;
        $self->_increment_processed_count();
    } elsif ( $element->{Name} ne 'cite' ) {
        $self->{_char_storage} =~ s/<\/?p>//g;
        if ( ( defined $self->_stack ) ) {
            my $current_hash     = pop @{ $self->_stack };
            my $parent_hash      = $self->_top( $self->_stack );
            my $current_hash_key = pop @{ $self->_names };

            if ( keys %{$current_hash} > 0 && $self->_char_storage ne "" ) {
                $current_hash->{comment} = $self->_char_storage;
                push @{ $parent_hash->{$current_hash_key} }, $current_hash;
            } elsif ( $self->_char_storage ne "" ) {
                push @{ $parent_hash->{$current_hash_key} },
                    { 'accumulated_text_12345' => $self->_char_storage };
            } elsif ( keys %{$current_hash} > 0 ) {
                push @{ $parent_hash->{$current_hash_key} }, $current_hash;
            }
            if ( $element->{Name} eq 'pub_list' ) {
                my @refs = ();

                foreach my $pub_record ( @{ $current_hash->{publication} } ) {
                    my $ref = Bio::Annotation::Reference->new;
                    my $loc = $pub_record->{location}->[0];
                    # TODO: Getting unset stuff here; should this be an error?
                    $ref->location(
                        sprintf("%s, %s-%s, %s, %s",
                        $pub_record->{journal}->[0]->{accumulated_text_12345} || '',
                        $loc->{firstpage} || '',
                        $loc->{lastpage}  || '',
                        $loc->{volume}    || '',
                        $pub_record->{year}->[0]->{accumulated_text_12345} || '')
                    );
                    $ref->title( $pub_record->{title}->[0]->{accumulated_text_12345} );
                    my $ttt = $pub_record->{author_list}->[0];

                    $ref->authors( $ttt->{accumulated_text_12345} );
                    $ref->medline( scalar( $ttt->{dbkey} ) )
                        if exists( $ttt->{db} ) && $ttt->{db} eq "MEDLINE";
                    push @refs, $ref;
                }
                $self->_term->add_reference(@refs);
            } elsif ( $element->{Name} eq 'name' ) {
                $self->_term->name( $self->_char_storage );
            } elsif ( $element->{Name} eq 'abstract' ) {
                $self->_term->definition( $self->_char_storage );
                $self->_cite_skip(0);
            } elsif ( $element->{Name} eq 'member_list' ) {
                my @refs = ();

                foreach my $db_xref ( @{ $current_hash->{db_xref} } ) {
                    push @refs,
                        Bio::Annotation::DBLink->new(
                        -database   => $db_xref->{db},
                        -primary_id => $db_xref->{dbkey}
                        );
                }
                $self->_term->add_dbxref(-dbxrefs => \@refs,
                                          -context => 'member_list');
            } elsif ( $element->{Name} eq 'sec_list' ) {
                my @refs = ();

                foreach my $sec_ac ( @{ $current_hash->{sec_ac} } ) {
                    push @refs, $sec_ac->{sec_ac};
                }
                $self->_term->add_secondary_id(@refs);
                $self->secondary_accessions_map->{ $self->_term->identifier } = \@refs;
            } elsif ( $element->{Name} eq 'example_list' ) {
                my @refs = ();

                foreach my $example ( @{ $current_hash->{examples} } ) {
                    push @refs,
                        Bio::Annotation::DBLink->new(
                        -database   => $example->{db_xref}->[0]->{db},
                        -primary_id => $example->{db_xref}->[0]->{dbkey},
                        -comment    => $example->{comment}
                        );
                }
                $self->_term->add_dbxref(-dbxrefs => \@refs,
                                         -context => 'example_list');
            } elsif ( $element->{Name} eq 'external_doc_list' ) {
                my @refs = ();

                foreach my $db_xref ( @{ $current_hash->{db_xref} } ) {
                    push @refs,
                        Bio::Annotation::DBLink->new(
                        -database   => $db_xref->{db},
                        -primary_id => $db_xref->{dbkey}
                        );
                }
                $self->_term->add_dbxref(-dbxrefs => \@refs,
                                         -context => 'external_doc_list');
            } elsif ( $element->{Name} eq 'class_list' ) {
                my @refs = ();

                foreach my $classification ( @{ $current_hash->{classification} } ) {
                    push @refs,
                        Bio::Annotation::DBLink->new(
                        -database   => $classification->{class_type},
                        -primary_id => $classification->{id}
                        );
                }
                $self->_term->add_dbxref(-dbxrefs => \@refs,
                                        -context => 'class_list');
            } elsif ( $element->{Name} eq 'deleted_entries' ) {
                my @refs = ();

                foreach my $del_ref ( @{ $current_hash->{del_ref} } ) {
                    my $term =
                        ( $self->ontology_engine->get_term_by_identifier( $del_ref->{id} ) )[0];

                    $term->is_obsolete(1) if defined $term;
                }
            }
        }
        $self->_char_storage('') if !$self->_cite_skip;
    }
}

=head2 secondary_accessions_map

 Title   : secondary_accessions_map
 Usage   : $obj->secondary_accessions_map($newval)
 Function:
 Example : $map = $interpro_handler->secondary_accessions_map();
 Returns : Reference to a hash that maps InterPro identifier to an
  array reference of secondary accessions following the InterPro
 xml schema.
 Args    : Empty hash reference


=cut

sub secondary_accessions_map {
    my ( $self, $value ) = @_;

    if ( defined $value ) {
        $self->{'secondary_accessions_map'} = $value;
    }

    return $self->{'secondary_accessions_map'};
}

=head2 _increment_record_count

 Title   : _increment_record_count
 Usage   :
 Function:
 Example :
 Returns :
 Args    :


=cut

sub _increment_record_count {
    $record_count++;
}

=head2 _increment_processed_count

 Title   : _increment_processed_count
 Usage   :
 Function:
 Example :
 Returns :
 Args    :


=cut

sub _increment_processed_count {
    $processed_count++;
    print STDERR $processed_count . "\n" if $processed_count % 100 == 0;
}

1;
