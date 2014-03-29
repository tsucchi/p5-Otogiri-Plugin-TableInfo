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
        my ($dsn, $user, $pass) = @{ $self->{connect_info} };
        my ($scheme, $driver, $attr_string, $attr_hash, $driver_dsn) = DBI->parse_dsn($dsn);
        my %attr = Otogiri::Plugin::TableInfo::_parse_driver_dsn($driver_dsn);
        $attr{user}     = $user if ( !exists $attr{user} );
        $attr{password} = $pass if ( !exists $attr{password} );
        my $cmd = Otogiri::Plugin::TableInfo::_build_pg_dump_command($table_name, %attr);
        my $result = `$cmd`;
        return $result;
    }
    return;
}

sub _build_pg_dump_command {
    my ($table_name, %args) = @_;
    my $cmd = "pg_dump ";
    $cmd .= "-d $args{dbname} " if ( exists $args{dbname} );
    $cmd .= "-h $args{host} "   if ( exists $args{host} );
    $cmd .= "-p $args{port} "   if ( exists $args{port} );
    $cmd .= "-U $args{user} "   if ( exists $args{user} );
    $cmd .= "-w --schema-only ";
    $cmd .= "-t $table_name";
    return $cmd;
}

sub _parse_driver_dsn {
    my ($driver_dsn) = @_;

    my @statements = split(qr/;/, $driver_dsn);
    my %result = ();
    for my $statement ( @statements ) {
        my ($lhs, $rhs) = map{ Otogiri::Plugin::TableInfo::_trim($_) } split(qr/=/, $statement);
        $result{$lhs} = $rhs;
    }
    return %result;
}

sub _trim {
    my ($string) = @_;
    $string =~ s/\A\s+//;
    $string =~ s/\s+\z//;
    return $string;
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

