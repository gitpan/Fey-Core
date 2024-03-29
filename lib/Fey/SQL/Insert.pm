package Fey::SQL::Insert;

use strict;
use warnings;

use Moose::Policy 'MooseX::Policy::SemiAffordanceAccessor';
use Moose;

use Fey::Validate
    qw( validate
        validate_pos
        SCALAR
        UNDEF
        OBJECT
        DBI_TYPE
      );

use Scalar::Util qw( blessed );


sub insert { return $_[0] }

{
    my $spec = { type => OBJECT,
                 callbacks =>
                 { 'is a (non-alias) column with a table' =>
                   sub {    $_[0]->isa('Fey::Column')
                         && $_[0]->table()
                         && ! $_[0]->is_alias()
                         && ! $_[0]->table()->is_alias() }
                 },
               };

    my $nullable_col_value_type =
    { type      => SCALAR|UNDEF|OBJECT,
      callbacks =>
      { 'literal, placeholder, scalar, or undef' =>
        sub {    ! blessed $_[0]
              || $_[0]->isa('Fey::Literal')
              || $_[0]->isa('Fey::Placeholder') }
      },
    };

    my $non_nullable_col_value_type =
        { type      => SCALAR|OBJECT,
          callbacks =>
          { 'literal, placeholder, or scalar' =>
            sub {    ! blessed $_[0]
                  || ( $_[0]->isa('Fey::Literal') && ! $_[0]->isa('Fey::Literal::Null') )
                  || $_[0]->isa('Fey::Placeholder') }
          },
        };

    sub into
    {
        my $self = shift;

        my $count = @_ ? scalar @_ : 1;
        my @cols = validate_pos( @_, ($spec) x $count );

        $self->{columns} = \@cols;

        for my $col ( @{ $self->{columns} } )
        {
            $self->{values_spec}{ $col->name() } =
                $col->is_nullable()
                ? $nullable_col_value_type
                : $non_nullable_col_value_type;
        }

        return $self;
    }
}

{
    sub values
    {
        my $self = shift;

        my %vals = validate( @_, $self->{values_spec} );

        for ( values %vals )
        {
            $_ = Fey::Literal->new_from_scalar($_)
                unless blessed $_;
        }

        push @{ $self->{values} }, \%vals;

        return $self;
    }
}

{
    my @spec = ( DBI_TYPE );

    sub sql
    {
        my $self  = shift;
        my ($dbh) = validate_pos( @_, @spec );

        return ( join ' ',
                 $self->_insert_clause($dbh),
                 $self->_into_clause($dbh),
                 $self->_values_clause($dbh),
               );
    }
}

sub _insert_clause
{
    return
        ( 'INSERT INTO '
          . $_[1]->quote_identifier( $_[0]->{columns}[0]->table()->name() )
        );
}

sub _into_clause
{
    return
        ( '('
          . ( join ', ',
              map { $_[1]->quote_identifier( $_->name() ) }
              @{ $_[0]->{columns} }
            )
          . ')'
        );
}

sub _values_clause
{
    my $self = shift;
    my $dbh  = shift;

    my @v;
    for my $vals ( @{ $self->{values} } )
    {
        my $v = '(';

        $v .=
            ( join ', ',
              map { $vals->{ $_->name() }->sql($dbh) }
              @{ $self->{columns} }
           );

        $v .= ')';

        push @v, $v;
    }

    return 'VALUES ' . join ',', @v;
}

no Moose;
__PACKAGE__->meta()->make_immutable();

1;

__END__

=head1 NAME

Fey::SQL::Insert - Represents a INSERT query

=head1 SYNOPSIS

  my $sql = Fey::SQL->new_insert();

  # INSERT INTO Part
  #             (part_id, name, quantity)
  #      VALUES
  #             (?, ?, ?)
  $sql->insert()->into($Part);
  my $ph = Fey::Placeholder->new();
  $sql->values( $ph, $ph, $ph );

  print $sql->sql($dbh);

=head1 DESCRIPTION

This class represents a C<INSERT> query.

=head1 METHODS

This class provides the following methods:

=head2 Constructor

To construct an object of this class, call C<< $query->insert() >> on
a C<Fey::SQL> object.

=head2 $insert->insert()

This method is basically a no-op that exists to so that L<Fey::SQL>
has something to call after it constructs an object in this class.

=head2 $insert->into()

This method specifies the C<INTO> clause of the query. It expects a
list of L<Fey::Column> and/or L<Fey::Table> objects, but not aliases.

If you pass a table object, then the C<INTO> will include all of that
table's column, in the order returned by the C<< $table->columns() >>
method.

Most RDBMS implementations only allow for a single table here, but
some (like MySQL) do allow for multi-table inserts.

=head2 $insert->values(...)

This method takes a list of values. Each value can be of the
following:

=over 4

=item * a plain scalar, including undef

This will be passed to C<< Fey::Literal->new_from_scalar() >>.

=item * C<Fey::Literal> object

=item * C<Fey::Placeholder> object

=back

=head2 $insert->sql()

Returns the full SQL statement which this object represents. A DBI
handle must be passed so that identifiers can be properly quoted.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 BUGS

See L<Fey> for details on how to report bugs.

=head1 COPYRIGHT & LICENSE

Copyright 2006-2008 Dave Rolsky, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
