package Otogiri::Plugin::TableInfo;
use 5.008005;
use strict;
use warnings;

use Otogiri;
use Otogiri::Plugin;
use DBIx::Inspector;

our $VERSION = "0.01";

our @EXPORT = qw(show_tables desc);

sub show_tables {
    my ($self) = @_;
    my $inspector = DBIx::Inspector->new(dbh => $self->dbh);
    my @tables = $inspector->tables;
    my @result = map { $_->name } $inspector->tables;
    return @result;
}

sub desc {
    my ($self, $table_name) = @_;
    my $inspector = DBIx::Inspector->new(dbh => $self->dbh);
    my $table = $inspector->table($table_name);

    return if ( !defined $table );

    my $driver_name = $self->{dsn}->{driver};

    if ( $driver_name eq 'mysql' ) {
        my ($row) = $self->search_by_sql("SHOW CREATE TABLE $table_name");
        return $row->{'Create Table'};
    }
    elsif ( $driver_name eq 'SQLite' ) {
        return $table->{SQLITE_SQL};
    }
    elsif ( $driver_name eq 'Pg' ) {
        die "not supported yet";
    }
    return;
}


1;
__END__

=encoding utf-8

=head1 NAME

Otogiri::Plugin::TableInfo - retrieve table information from database

=head1 SYNOPSIS

    use Otogiri::Plugin::TableInfo;
    my $db = Otogiri->new( connect_info => [ ... ] );
    $db->load_plugin('TableInfo');
    my @table_names = $db->show_tables();


=head1 DESCRIPTION

Otogiri::Plugin::TableInfo is Otogiri plugin to fetch table information from database.

=head1 METHODS

=head2 my @table_names = $self->show_tables();

returns table names in database.

=head2 my $create_table_ddl = $self->desc($table_name);

returns create table statement like MySQL's 'show create table'.

=head1 LICENSE

Copyright (C) Takuya Tsuchida.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Takuya Tsuchida E<lt>tsucchi@cpan.orgE<gt>

=cut

