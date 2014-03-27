package Otogiri::Plugin::TableInfo;
use 5.008005;
use strict;
use warnings;

use Otogiri;
use Otogiri::Plugin;
use DBIx::Inspector;

our $VERSION = "0.01";

our @EXPORT = qw(show_tables);

sub show_tables {
    my ($self) = @_;
    my $inspector = DBIx::Inspector->new(dbh => $self->dbh);
    my @tables = $inspector->tables;
    my @result = map { $_->name } $inspector->tables;
    return @result;
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

=head1 LICENSE

Copyright (C) Takuya Tsuchida.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Takuya Tsuchida E<lt>tsucchi@cpan.orgE<gt>

=cut

