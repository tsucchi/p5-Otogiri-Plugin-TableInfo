use strict;
use warnings;
use Test::More;
use Otogiri;
use Otogiri::Plugin;
use List::MoreUtils qw(any none);
#use DBIx::QueryLog;

my $dbfile  = ':memory:';

my $db = Otogiri->new( connect_info => ["dbi:SQLite:dbname=$dbfile", '', '', { RaiseError => 1, PrintError => 0 }] );
$db->load_plugin('TableInfo');

ok( $db->can('show_tables') );

my @sql_statements = split /\n\n/, <<EOSQL;
PRAGMA foreign_keys = ON;

CREATE TABLE person (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT    NOT NULL,
  age  INTEGER NOT NULL DEFAULT 20
);

CREATE TABLE detective (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  person_id INTEGER NOT NULL,
  toys      TEXT  NOT NULL,
  FOREIGN KEY(person_id) REFERENCES person(id)
);
EOSQL
$db->do($_) for @sql_statements;

subtest 'show_tables(all)', sub {
    my @result = $db->show_tables();
    # @result contains system table.(sqlite_sequence)
    ok( any { $_ eq 'detective' } @result );
    ok( any { $_ eq 'person' }    @result );
};

subtest 'show_tables(with regex)', sub {
    my @result = $db->show_tables(qr/pe/);
    # @result contains system table.(sqlite_sequence)
    ok( none { $_ eq 'detective' } @result );
    ok( any { $_ eq 'person' }    @result );
};


done_testing;
