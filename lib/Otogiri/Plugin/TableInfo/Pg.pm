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

    my $result = "CREATE TABLE " . $table->name . " (\n";
    $result .= $self->_build_column_defs($table);
    $result .= ");\n";
    $result .= $self->_build_sequence_defs($table);
    $result .= $self->_build_pk_defs($table);
    $result .= $self->_build_index_defs($table);
    $result .= $self->_build_fk_defs($table);
    return $result;
}

sub _build_column_defs {
    my ($self, $table) = @_;
    my $result = "";
    for my $column ( $table->columns() ) {
        my $column_name = $self->{keywords}->quote($column->name); #quote column name if it is need.
        $result .= "    " . $column_name . " " . $column->type_name;
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
    my ($self, $table) = @_;
    my @rows = sort { $a->{indexname} cmp $b->{indexname} } $self->{table_info}->select('pg_indexes', { tablename => $table->name });
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

sub _keywords {
    return (
        'A',
        'ABORT',
        'ABS',
        'ABSENT',
        'ABSOLUTE',
        'ACCESS',
        'ACCORDING',
        'ACTION',
        'ADA',
        'ADD',
        'ADMIN',
        'AFTER',
        'AGGREGATE',
        'ALL',
        'ALLOCATE',
        'ALSO',
        'ALTER',
        'ALWAYS',
        'ANALYSE',
        'ANALYZE',
        'AND',
        'ANY',
        'ARE',
        'ARRAY',
        'ARRAY_AGG',
        'ARRAY_MAX_CARDINALITY',
        'AS',
        'ASC',
        'ASENSITIVE',
        'ASSERTION',
        'ASSIGNMENT',
        'ASYMMETRIC',
        'AT',
        'ATOMIC',
        'ATTRIBUTE',
        'ATTRIBUTES',
        'AUTHORIZATION',
        'AVG',
        'BACKWARD',
        'BASE64',
        'BEFORE',
        'BEGIN',
        'BEGIN_FRAME',
        'BEGIN_PARTITION',
        'BERNOULLI',
        'BETWEEN',
        'BIGINT',
        'BINARY',
        'BIT',
        'BIT_LENGTH',
        'BLOB',
        'BLOCKED',
        'BOM',
        'BOOLEAN',
        'BOTH',
        'BREADTH',
        'BY',
        'C',
        'CACHE',
        'CALL',
        'CALLED',
        'CARDINALITY',
        'CASCADE',
        'CASCADED',
        'CASE',
        'CAST',
        'CATALOG',
        'CATALOG_NAME',
        'CEIL',
        'CEILING',
        'CHAIN',
        'CHAR',
        'CHARACTER',
        'CHARACTERISTICS',
        'CHARACTERS',
        'CHARACTER_LENGTH',
        'CHARACTER_SET_CATALOG',
        'CHARACTER_SET_NAME',
        'CHARACTER_SET_SCHEMA',
        'CHAR_LENGTH',
        'CHECK',
        'CHECKPOINT',
        'CLASS',
        'CLASS_ORIGIN',
        'CLOB',
        'CLOSE',
        'CLUSTER',
        'COALESCE',
        'COBOL',
        'COLLATE',
        'COLLATION',
        'COLLATION_CATALOG',
        'COLLATION_NAME',
        'COLLATION_SCHEMA',
        'COLLECT',
        'COLUMN',
        'COLUMNS',
        'COLUMN_NAME',
        'COMMAND_FUNCTION',
        'COMMAND_FUNCTION_CODE',
        'COMMENT',
        'COMMENTS',
        'COMMIT',
        'COMMITTED',
        'CONCURRENTLY',
        'CONDITION',
        'CONDITION_NUMBER',
        'CONFIGURATION',
        'CONNECT',
        'CONNECTION',
        'CONNECTION_NAME',
        'CONSTRAINT',
        'CONSTRAINTS',
        'CONSTRAINT_CATALOG',
        'CONSTRAINT_NAME',
        'CONSTRAINT_SCHEMA',
        'CONSTRUCTOR',
        'CONTAINS',
        'CONTENT',
        'CONTINUE',
        'CONTROL',
        'CONVERSION',
        'CONVERT',
        'COPY',
        'CORR',
        'CORRESPONDING',
        'COST',
        'COUNT',
        'COVAR_POP',
        'COVAR_SAMP',
        'CREATE',
        'CROSS',
        'CSV',
        'CUBE',
        'CUME_DIST',
        'CURRENT',
        'CURRENT_CATALOG',
        'CURRENT_DATE',
        'CURRENT_DEFAULT_TRANSFORM_GROUP',
        'CURRENT_PATH',
        'CURRENT_ROLE',
        'CURRENT_ROW',
        'CURRENT_SCHEMA',
        'CURRENT_TIME',
        'CURRENT_TIMESTAMP',
        'CURRENT_TRANSFORM_GROUP_FOR_TYPE',
        'CURRENT_USER',
        'CURSOR',
        'CURSOR_NAME',
        'CYCLE',
        'DATA',
        'DATABASE',
        'DATALINK',
        'DATE',
        'DATETIME_INTERVAL_CODE',
        'DATETIME_INTERVAL_PRECISION',
        'DAY',
        'DB',
        'DEALLOCATE',
        'DEC',
        'DECIMAL',
        'DECLARE',
        'DEFAULT',
        'DEFAULTS',
        'DEFERRABLE',
        'DEFERRED',
        'DEFINED',
        'DEFINER',
        'DEGREE',
        'DELETE',
        'DELIMITER',
        'DELIMITERS',
        'DENSE_RANK',
        'DEPTH',
        'DEREF',
        'DERIVED',
        'DESC',
        'DESCRIBE',
        'DESCRIPTOR',
        'DETERMINISTIC',
        'DIAGNOSTICS',
        'DICTIONARY',
        'DISABLE',
        'DISCARD',
        'DISCONNECT',
        'DISPATCH',
        'DISTINCT',
        'DLNEWCOPY',
        'DLPREVIOUSCOPY',
        'DLURLCOMPLETE',
        'DLURLCOMPLETEONLY',
        'DLURLCOMPLETEWRITE',
        'DLURLPATH',
        'DLURLPATHONLY',
        'DLURLPATHWRITE',
        'DLURLSCHEME',
        'DLURLSERVER',
        'DLVALUE',
        'DO',
        'DOCUMENT',
        'DOMAIN',
        'DOUBLE',
        'DROP',
        'DYNAMIC',
        'DYNAMIC_FUNCTION',
        'DYNAMIC_FUNCTION_CODE',
        'EACH',
        'ELEMENT',
        'ELSE',
        'EMPTY',
        'ENABLE',
        'ENCODING',
        'ENCRYPTED',
        'END',
        'END-EXEC',
        'END_FRAME',
        'END_PARTITION',
        'ENFORCED',
        'ENUM',
        'EQUALS',
        'ESCAPE',
        'EVENT',
        'EVERY',
        'EXCEPT',
        'EXCEPTION',
        'EXCLUDE',
        'EXCLUDING',
        'EXCLUSIVE',
        'EXEC',
        'EXECUTE',
        'EXISTS',
        'EXP',
        'EXPLAIN',
        'EXPRESSION',
        'EXTENSION',
        'EXTERNAL',
        'EXTRACT',
        'FALSE',
        'FAMILY',
        'FETCH',
        'FILE',
        'FILTER',
        'FINAL',
        'FIRST',
        'FIRST_VALUE',
        'FLAG',
        'FLOAT',
        'FLOOR',
        'FOLLOWING',
        'FOR',
        'FORCE',
        'FOREIGN',
        'FORTRAN',
        'FORWARD',
        'FOUND',
        'FRAME_ROW',
        'FREE',
        'FREEZE',
        'FROM',
        'FS',
        'FULL',
        'FUNCTION',
        'FUNCTIONS',
        'FUSION',
        'G',
        'GENERAL',
        'GENERATED',
        'GET',
        'GLOBAL',
        'GO',
        'GOTO',
        'GRANT',
        'GRANTED',
        'GREATEST',
        'GROUP',
        'GROUPING',
        'GROUPS',
        'HANDLER',
        'HAVING',
        'HEADER',
        'HEX',
        'HIERARCHY',
        'HOLD',
        'HOUR',
        'ID',
        'IDENTITY',
        'IF',
        'IGNORE',
        'ILIKE',
        'IMMEDIATE',
        'IMMEDIATELY',
        'IMMUTABLE',
        'IMPLEMENTATION',
        'IMPLICIT',
        'IMPORT',
        'IN',
        'INCLUDING',
        'INCREMENT',
        'INDENT',
        'INDEX',
        'INDEXES',
        'INDICATOR',
        'INHERIT',
        'INHERITS',
        'INITIALLY',
        'INLINE',
        'INNER',
        'INOUT',
        'INPUT',
        'INSENSITIVE',
        'INSERT',
        'INSTANCE',
        'INSTANTIABLE',
        'INSTEAD',
        'INT',
        'INTEGER',
        'INTEGRITY',
        'INTERSECT',
        'INTERSECTION',
        'INTERVAL',
        'INTO',
        'INVOKER',
        'IS',
        'ISNULL',
        'ISOLATION',
        'JOIN',
        'K',
        'KEY',
        'KEY_MEMBER',
        'KEY_TYPE',
        'LABEL',
        'LAG',
        'LANGUAGE',
        'LARGE',
        'LAST',
        'LAST_VALUE',
        'LATERAL',
        'LC_COLLATE',
        'LC_CTYPE',
        'LEAD',
        'LEADING',
        'LEAKPROOF',
        'LEAST',
        'LEFT',
        'LENGTH',
        'LEVEL',
        'LIBRARY',
        'LIKE',
        'LIKE_REGEX',
        'LIMIT',
        'LINK',
        'LISTEN',
        'LN',
        'LOAD',
        'LOCAL',
        'LOCALTIME',
        'LOCALTIMESTAMP',
        'LOCATION',
        'LOCATOR',
        'LOCK',
        'LOWER',
        'M',
        'MAP',
        'MAPPING',
        'MATCH',
        'MATCHED',
        'MATERIALIZED',
        'MAX',
        'MAXVALUE',
        'MAX_CARDINALITY',
        'MEMBER',
        'MERGE',
        'MESSAGE_LENGTH',
        'MESSAGE_OCTET_LENGTH',
        'MESSAGE_TEXT',
        'METHOD',
        'MIN',
        'MINUTE',
        'MINVALUE',
        'MOD',
        'MODE',
        'MODIFIES',
        'MODULE',
        'MONTH',
        'MORE',
        'MOVE',
        'MULTISET',
        'MUMPS',
        'NAME',
        'NAMES',
        'NAMESPACE',
        'NATIONAL',
        'NATURAL',
        'NCHAR',
        'NCLOB',
        'NESTING',
        'NEW',
        'NEXT',
        'NFC',
        'NFD',
        'NFKC',
        'NFKD',
        'NIL',
        'NO',
        'NONE',
        'NORMALIZE',
        'NORMALIZED',
        'NOT',
        'NOTHING',
        'NOTIFY',
        'NOTNULL',
        'NOWAIT',
        'NTH_VALUE',
        'NTILE',
        'NULL',
        'NULLABLE',
        'NULLIF',
        'NULLS',
        'NUMBER',
        'NUMERIC',
        'OBJECT',
        'OCCURRENCES_REGEX',
        'OCTETS',
        'OCTET_LENGTH',
        'OF',
        'OFF',
        'OFFSET',
        'OIDS',
        'OLD',
        'ON',
        'ONLY',
        'OPEN',
        'OPERATOR',
        'OPTION',
        'OPTIONS',
        'OR',
        'ORDER',
        'ORDERING',
        'ORDINALITY',
        'OTHERS',
        'OUT',
        'OUTER',
        'OUTPUT',
        'OVER',
        'OVERLAPS',
        'OVERLAY',
        'OVERRIDING',
        'OWNED',
        'OWNER',
        'P',
        'PAD',
        'PARAMETER',
        'PARAMETER_MODE',
        'PARAMETER_NAME',
        'PARAMETER_ORDINAL_POSITION',
        'PARAMETER_SPECIFIC_CATALOG',
        'PARAMETER_SPECIFIC_NAME',
        'PARAMETER_SPECIFIC_SCHEMA',
        'PARSER',
        'PARTIAL',
        'PARTITION',
        'PASCAL',
        'PASSING',
        'PASSTHROUGH',
        'PASSWORD',
        'PATH',
        'PERCENT',
        'PERCENTILE_CONT',
        'PERCENTILE_DISC',
        'PERCENT_RANK',
        'PERIOD',
        'PERMISSION',
        'PLACING',
        'PLANS',
        'PLI',
        'PORTION',
        'POSITION',
        'POSITION_REGEX',
        'POWER',
        'PRECEDES',
        'PRECEDING',
        'PRECISION',
        'PREPARE',
        'PREPARED',
        'PRESERVE',
        'PRIMARY',
        'PRIOR',
        'PRIVILEGES',
        'PROCEDURAL',
        'PROCEDURE',
        'PROGRAM',
        'PUBLIC',
        'QUOTE',
        'RANGE',
        'RANK',
        'READ',
        'READS',
        'REAL',
        'REASSIGN',
        'RECHECK',
        'RECOVERY',
        'RECURSIVE',
        'REF',
        'REFERENCES',
        'REFERENCING',
        'REFRESH',
        'REGR_AVGX',
        'REGR_AVGY',
        'REGR_COUNT',
        'REGR_INTERCEPT',
        'REGR_R2',
        'REGR_SLOPE',
        'REGR_SXX',
        'REGR_SXY',
        'REGR_SYY',
        'REINDEX',
        'RELATIVE',
        'RELEASE',
        'RENAME',
        'REPEATABLE',
        'REPLACE',
        'REPLICA',
        'REQUIRING',
        'RESET',
        'RESPECT',
        'RESTART',
        'RESTORE',
        'RESTRICT',
        'RESULT',
        'RETURN',
        'RETURNED_CARDINALITY',
        'RETURNED_LENGTH',
        'RETURNED_OCTET_LENGTH',
        'RETURNED_SQLSTATE',
        'RETURNING',
        'RETURNS',
        'REVOKE',
        'RIGHT',
        'ROLE',
        'ROLLBACK',
        'ROLLUP',
        'ROUTINE',
        'ROUTINE_CATALOG',
        'ROUTINE_NAME',
        'ROUTINE_SCHEMA',
        'ROW',
        'ROWS',
        'ROW_COUNT',
        'ROW_NUMBER',
        'RULE',
        'SAVEPOINT',
        'SCALE',
        'SCHEMA',
        'SCHEMA_NAME',
        'SCOPE',
        'SCOPE_CATALOG',
        'SCOPE_NAME',
        'SCOPE_SCHEMA',
        'SCROLL',
        'SEARCH',
        'SECOND',
        'SECTION',
        'SECURITY',
        'SELECT',
        'SELECTIVE',
        'SELF',
        'SENSITIVE',
        'SEQUENCE',
        'SEQUENCES',
        'SERIALIZABLE',
        'SERVER',
        'SERVER_NAME',
        'SESSION',
        'SESSION_USER',
        'SET',
        'SETOF',
        'SETS',
        'SHARE',
        'SHOW',
        'SIMILAR',
        'SIMPLE',
        'SIZE',
        'SMALLINT',
        'SNAPSHOT',
        'SOME',
        'SOURCE',
        'SPACE',
        'SPECIFIC',
        'SPECIFICTYPE',
        'SPECIFIC_NAME',
        'SQL',
        'SQLCODE',
        'SQLERROR',
        'SQLEXCEPTION',
        'SQLSTATE',
        'SQLWARNING',
        'SQRT',
        'STABLE',
        'STANDALONE',
        'START',
        'STATE',
        'STATEMENT',
        'STATIC',
        'STATISTICS',
        'STDDEV_POP',
        'STDDEV_SAMP',
        'STDIN',
        'STDOUT',
        'STORAGE',
        'STRICT',
        'STRIP',
        'STRUCTURE',
        'STYLE',
        'SUBCLASS_ORIGIN',
        'SUBMULTISET',
        'SUBSTRING',
        'SUBSTRING_REGEX',
        'SUCCEEDS',
        'SUM',
        'SYMMETRIC',
        'SYSID',
        'SYSTEM',
        'SYSTEM_TIME',
        'SYSTEM_USER',
        'T',
        'TABLE',
        'TABLES',
        'TABLESAMPLE',
        'TABLESPACE',
        'TABLE_NAME',
        'TEMP',
        'TEMPLATE',
        'TEMPORARY',
        'TEXT',
        'THEN',
        'TIES',
        'TIME',
        'TIMESTAMP',
        'TIMEZONE_HOUR',
        'TIMEZONE_MINUTE',
        'TO',
        'TOKEN',
        'TOP_LEVEL_COUNT',
        'TRAILING',
        'TRANSACTION',
        'TRANSACTIONS_COMMITTED',
        'TRANSACTIONS_ROLLED_BACK',
        'TRANSACTION_ACTIVE',
        'TRANSFORM',
        'TRANSFORMS',
        'TRANSLATE',
        'TRANSLATE_REGEX',
        'TRANSLATION',
        'TREAT',
        'TRIGGER',
        'TRIGGER_CATALOG',
        'TRIGGER_NAME',
        'TRIGGER_SCHEMA',
        'TRIM',
        'TRIM_ARRAY',
        'TRUE',
        'TRUNCATE',
        'TRUSTED',
        'TYPE',
        'TYPES',
        'UESCAPE',
        'UNBOUNDED',
        'UNCOMMITTED',
        'UNDER',
        'UNENCRYPTED',
        'UNION',
        'UNIQUE',
        'UNKNOWN',
        'UNLINK',
        'UNLISTEN',
        'UNLOGGED',
        'UNNAMED',
        'UNNEST',
        'UNTIL',
        'UNTYPED',
        'UPDATE',
        'UPPER',
        'URI',
        'USAGE',
        'USER',
        'USER_DEFINED_TYPE_CATALOG',
        'USER_DEFINED_TYPE_CODE',
        'USER_DEFINED_TYPE_NAME',
        'USER_DEFINED_TYPE_SCHEMA',
        'USING',
        'VACUUM',
        'VALID',
        'VALIDATE',
        'VALIDATOR',
        'VALUE',
        'VALUES',
        'VALUE_OF',
        'VARBINARY',
        'VARCHAR',
        'VARIADIC',
        'VARYING',
        'VAR_POP',
        'VAR_SAMP',
        'VERBOSE',
        'VERSION',
        'VERSIONING',
        'VIEW',
        'VOLATILE',
        'WHEN',
        'WHENEVER',
        'WHERE',
        'WHITESPACE',
        'WIDTH_BUCKET',
        'WINDOW',
        'WITH',
        'WITHIN',
        'WITHOUT',
        'WORK',
        'WRAPPER',
        'WRITE',
        'XML',
        'XMLAGG',
        'XMLATTRIBUTES',
        'XMLBINARY',
        'XMLCAST',
        'XMLCOMMENT',
        'XMLCONCAT',
        'XMLDECLARATION',
        'XMLDOCUMENT',
        'XMLELEMENT',
        'XMLEXISTS',
        'XMLFOREST',
        'XMLITERATE',
        'XMLNAMESPACES',
        'XMLPARSE',
        'XMLPI',
        'XMLQUERY',
        'XMLROOT',
        'XMLSCHEMA',
        'XMLSERIALIZE',
        'XMLTABLE',
        'XMLTEXT',
        'XMLVALIDATE',
        'YEAR',
        'YES',
        'ZONE',
    );
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
