package Otogiri::Plugin::TableInfo;
use 5.008005;
use strict;
use warnings;

use Otogiri;
use Otogiri::Plugin;
use DBIx::Inspector;
use Otogiri::Plugin::TableInfo::Pg;

our $VERSION = "0.01";

our @EXPORT = qw(show_tables show_create_table desc);

sub show_tables {
    my ($self, $like_regex) = @_;
    my $inspector = DBIx::Inspector->new(dbh => $self->dbh);
    my @tables = $inspector->tables;
    my @result = map { $_->name } $inspector->tables;
    @result = grep { $_ =~ /$like_regex/ } @result if ( defined $like_regex );
    return @result;
}

sub show_create_table {
    my ($self, $table_name) = @_;
    return $self->desc($table_name);
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
        my $pg = Otogiri::Plugin::TableInfo::Pg->new($self);
        return $pg->desc($table_name);
    }
    return;
}



1;
__END__

=encoding utf-8

=for stopwords desc

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

=head2 my @table_names = $self->show_tables([$like_regex]);

returns table names in database.

parameter C<$like_regex> is optional. If it is passed, table name is filtered by regex like MySQL's C<SHOW TABLES LIKE ...> statement.

    my @table_names = $db->show_tables(qr/^user_/); # return table names that starts with 'user_'

If C<$like_regex> is not passed, all table_names in current database are returned.

=head2 my $create_table_ddl = $self->desc($table_name);

returns create table statement like MySQL's 'show create table'.

=head1 LICENSE

Copyright (C) Takuya Tsuchida.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Takuya Tsuchida E<lt>tsucchi@cpan.orgE<gt>

=cut

