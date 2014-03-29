package Otogiri::Plugin::TableInfo::Pg;
use 5.008005;
use strict;
use warnings;
use DBI;

sub new {
    my ($class, $table_info) = @_;
    my $self = {
        table_info => $table_info,
    };
    bless $self, $class;
}


sub desc {
    my ($self, $table_name) = @_;
    my ($dsn, $user, $pass) = @{ $self->{table_info}->{connect_info} };
    my ($scheme, $driver, $attr_string, $attr_hash, $driver_dsn) = DBI->parse_dsn($dsn);
    my %attr = $self->_parse_driver_dsn($driver_dsn);
    $attr{user}     = $user if ( !exists $attr{user} );
    $attr{password} = $pass if ( !exists $attr{password} );
    my $cmd = $self->_build_pg_dump_command($table_name, %attr);
    my $result = `$cmd`;
    return $result;
}


sub _build_pg_dump_command {
    my ($self, $table_name, %args) = @_;
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
    my ($self, $driver_dsn) = @_;

    my @statements = split(qr/;/, $driver_dsn);
    my %result = ();
    for my $statement ( @statements ) {
        my ($variable_name, $value) = map{ $self->_trim($_) } split(qr/=/, $statement);
        $result{$variable_name} = $value;
    }
    return %result;
}

sub _trim {
    my ($self, $string) = @_;
    $string =~ s/\A\s+//;
    $string =~ s/\s+\z//;
    return $string;
}

1;
__END__

=encoding utf-8

=head1 NAME

Otogiri::Plugin::TableInfo::Pg - build CREATE TABLE statement for PostgreSQL

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


=head2 my $create_table_ddl = $self->desc($table_name);

returns create table statement like MySQL's 'show create table'.

parameter C<$like_regex> is optional. If it is passed, table name is filtered by regex like MySQL's C<SHOW TABLES LIKE ...> statement.

    my @table_names = $db->show_tables(qr/^user_/); # return table names that starts with 'user_'

If C<$like_regex> is not passed, all table_names in current database are returned.



=cut
