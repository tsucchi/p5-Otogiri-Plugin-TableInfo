package Otogiri::Plugin::TableInfo::Pg;
use 5.008005;
use strict;
use warnings;
use DBI;
use DBIx::Inspector;
use List::MoreUtils qw(any);
use Otogiri::Plugin::TableInfo::PgKeywords;

sub new {
    my ($class, $table_info) = @_;
    my $keywords = Otogiri::Plugin::TableInfo::PgKeywords->new();
    my $self = {
        table_info => $table_info,
        keywords   => $keywords,
    };
    bless $self, $class;
}


sub desc {
    my ($self, $table_name) = @_;
    if ( !defined $self->{table_info}->{use_pg_dump} || $self->{table_info}->{use_pg_dump} ) { # default is using pg_dump
        return $self->_desc_by_pg_dump($table_name);
    }
    return $self->_desc_by_inspector($table_name);
}

sub _desc_by_inspector {
    my ($self, $table_name) = @_;
    my $inspector = DBIx::Inspector->new(dbh => $self->{table_info}->dbh);
    my $table = $inspector->table($table_name);

    return if ( !defined $table );

    my @indexes = $self->{table_info}->select('pg_indexes', { tablename => $table->name }, { order_by => 'indexname' });
    my $result = "CREATE TABLE " . $table->name . " (\n";
    $result .= $self->_build_column_defs($table);
    $result .= ");\n";
    $result .= $self->_build_sequence_defs($table);
    $result .= $self->_build_pk_defs($table);
    $result .= $self->_build_uk_defs($table, @indexes);
    $result .= $self->_build_index_defs($table, @indexes);
    $result .= $self->_build_fk_defs($table);
    return $result;
}

sub _build_column_defs {
    my ($self, $table) = @_;
    my $result = "";
    for my $column ( $table->columns() ) {
        my $column_name = $self->{keywords}->quote($column->name); #quote column name if it is need.
        $result .= "    " . $column_name . " " . $column->{PG_TYPE};
        $result .= " DEFAULT " . $column->column_def if ( defined $column->column_def && !$self->_is_sequence_column($column) );
        $result .= " NOT NULL" if ( !$column->nullable );
        $result .= ",\n";
    }
    $result =~ s/,\n\z/\n/;
    return $result;
}

sub _build_sequence_defs {
    my ($self, $table) = @_;
    my $result = "";
    my @sequence_columns = grep { $self->_is_sequence_column($_) } $table->columns();
    for my $column ( @sequence_columns ) {
        my $sequence_name = $self->_parse_sequence_name($column);
        $result .= $self->_build_create_sequence_defs($sequence_name);
        $result .= "ALTER SEQUENCE " . $sequence_name . " OWNED BY " . $table->name . "." . $column->name . ";\n";
        $result .= "ALTER TABLE ONLY " . $table->name . " ALTER COLUMN " . $column->name . " SET DEFAULT " . $column->column_def . ";\n";
    }
    return $result;
}

sub _parse_sequence_name {
    my ($self, $column) = @_;
    if ( $column->column_def =~ qr/^nextval\('([^']+)'::regclass\)/ ) {
        return $1;
    }
    return;
}

sub _build_create_sequence_defs {
    my ($self, $sequence_name) = @_;
    my ($row) = $self->{table_info}->select($sequence_name);
    my $result = "CREATE SEQUENCE $sequence_name\n";
    $result .= "    START WITH " . $row->{start_value} . "\n";
    $result .= "    INCREMENT BY " . $row->{increment_by} . "\n";
    if ( $row->{min_value} eq '1' ) {
        $result .= "    NO MINVALUE\n";
    }
    else {
        $result .= "    MINVALUE " . $row->{min_value} . "\n";
    }

    if ( $row->{max_value} eq '9223372036854775807' ) {
        $result .= "    NO MAXVALUE\n";
    }
    else {
        $result .= "    MAXVALUE " . $row->{max_value} . "\n";
    }

    $result .= "    CACHE " . $row->{cache_value} . ";\n";
    return $result;
}

sub _is_sequence_column {
    my ($self, $column) = @_;
    my $default_value = $column->column_def;
    return if ( !defined $default_value );
    return $default_value =~ qr/^nextval\(/;
}

sub _build_pk_defs {
    my ($self, $table) = @_;
    my $result = "";
    for my $column ( $table->primary_key() ) {
        $result .= "ALTER TABLE ONLY " . $table->name . "\n";
        $result .= "    ADD CONSTRAINT " . $column->{PG_COLUMN} . " PRIMARY KEY (" . $column->name . ");\n";
    }
    return $result;
}

sub _build_index_defs {
    my ($self, $table, @indexes) = @_;

    my @rows = grep { $_->{indexdef} !~ qr/\ACREATE UNIQUE INDEX/ } @indexes;

    my $result = '';
    for my $row ( @rows ) {
        next if ( $self->_is_pk($table, $row->{indexname}) );
        $result .= $row->{indexdef} . ";\n";
    }
    return $result;
}

sub _is_pk {
    my ($self, $table, $column_name) = @_;
    return any { $_->{PK_NAME} eq $column_name } $table->primary_key();
}

sub _build_uk_defs {
    my ($self, $table, @indexes) = @_;
    my @unique_indexes = grep {
        $_->{indexdef} =~ qr/\ACREATE UNIQUE INDEX/ && !$self->_is_pk($table, $_->{indexname})
    } @indexes;

    my $result = '';
    # TODO: これは異常なので、pg_dump 側を変換して素のindexdef を使うようにするべき
    # return join(";\n", map{ $_->{indexdef} } @indexes);
    for my $unique_index ( @unique_indexes ) {
        my $columns = undef;
        if ( $unique_index->{indexdef} =~ qr/\(([^(]+)\)\z/ ) {
            $columns = $1;
        }
        next if ( !defined $columns );

        if ( $unique_index->{indexname} =~ qr/index\z/ ) {
            $result .= $unique_index->{indexdef} . ";\n";
        }
        else {
            $result .= "ALTER TABLE ONLY " . $table->name . "\n";
            $result .= "    ADD CONSTRAINT " . $unique_index->{indexname} . " UNIQUE (" . $columns . ");\n";
        }
    }
    return $result;
}

sub _build_fk_defs {
    my ($self, $table) = @_;
    my $result = '';
    # UPDATE_RULE and DELETE_RULE are described in http://search.cpan.org/dist/DBI/DBI.pm#foreign_key_info
    my %rule = (
        0 => 'CASCADE',
        1 => 'RESTRICT',
        2 => 'SET NULL',
        #3 => 'NO ACTION', # If NO ACTION, ON UPDATE/DELETE statament is not exist.
        4 => 'SET DEFAULT',
    );

    for my $fk_info ( $table->fk_foreign_keys() ) {
        $result .= "ALTER TABLE ONLY " . $table->name . "\n";
        $result .= "    ADD CONSTRAINT " . $fk_info->fk_name . " FOREIGN KEY (" . $fk_info->fkcolumn_name . ")";
        $result .= " REFERENCES " . $fk_info->pktable_name . "(" . $fk_info->pkcolumn_name . ")";
        $result .= " ON UPDATE " . $rule{$fk_info->{UPDATE_RULE}} if ( exists $rule{$fk_info->{UPDATE_RULE}} );
        $result .= " ON DELETE " . $rule{$fk_info->{DELETE_RULE}} if ( exists $rule{$fk_info->{DELETE_RULE}} );
        $result .= " DEFERRABLE" if ( $fk_info->deferability ne '7' );
        $result .= ";\n";
    }
    return $result;
}

sub _desc_by_pg_dump {
    my ($self, $table_name) = @_;
    my ($dsn, $user, $pass) = @{ $self->{table_info}->{connect_info} };
    my ($scheme, $driver, $attr_string, $attr_hash, $driver_dsn) = DBI->parse_dsn($dsn);
    my %attr = $self->_parse_driver_dsn($driver_dsn);
    $attr{user}     = $user if ( !exists $attr{user} );
    $attr{password} = $pass if ( !exists $attr{password} );
    my $cmd = $self->_build_pg_dump_command($table_name, %attr);
    my $result = `$cmd`;
    return $self->_trim_result($result);
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

sub _build_pg_dump_command {
    my ($self, $table_name, %args) = @_;
    my $cmd = "pg_dump ";
    $cmd .= "-h $args{host} "   if ( exists $args{host} );
    $cmd .= "-p $args{port} "   if ( exists $args{port} );
    $cmd .= "-U $args{user} "   if ( exists $args{user} );
    $cmd .= "-w --schema-only ";
    $cmd .= "-t $table_name ";
    $cmd .= "$args{dbname}";
    return $cmd;
}

sub _trim_result {
    my ($self, $input) = @_;
    my @lines = split(qr/\n/, $input);
    my $result = "";
    for my $line ( @lines ) {
        next if ( $line =~ qr/\A--/ );
        next if ( $line =~ qr/\A\s*\z/ );
        next if ( $line =~ qr/\ASET\s+/ );
        next if ( $line =~ qr/\AREVOKE\s+/ );
        next if ( $line =~ qr/\AGRANT\s+/ );
        next if ( $line =~ qr/\AALTER TABLE\s+/ && $line =~ qr/\s+OWNER TO\s+/ );
        $result .= "$line\n";
    }
    return $result;
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
