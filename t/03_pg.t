use strict;
use warnings;
use Test::More;
use DBI;
use Otogiri;
use Otogiri::Plugin;
use Test::Differences;
unified_diff;

use t::Util;
use Test::Requires 'Test::PostgreSQL';



my $pg = Test::PostgreSQL->new(
    my_cnf => {
        'skip-networking' => '',
    }
) or plan skip_all => $Test::PostgreSQL::errstr;

Otogiri->load_plugin('TableInfo');

my $db = Otogiri->new( connect_info => [$pg->dsn(dbname => 'test'), '', '', { RaiseError => 1, PrintError => 0 }] );
my $sql_person = <<'EOF';
CREATE TABLE person (
    id   serial       PRIMARY KEY,
    name character(48) NOT NULL,
    age  integer
);
EOF

$db->dbh->do($sql_person);

# detective has 'toys' (supernatural power). If you don't know this, watch 'Detective Opera MilkyHolmes'!
my $sql_detective = <<'EOF';
CREATE TABLE detective (
    person_id integer PRIMARY KEY,
    toys      text    NOT NULL,
    FOREIGN KEY (person_id) REFERENCES person(id) ON UPDATE SET NULL ON DELETE RESTRICT
);
EOF

$db->dbh->do($sql_detective);
$db->dbh->do('CREATE INDEX ON detective (toys)');

# "position" is reserved word (it is escaped)
my $sql_baseball_player = <<'EOF';
CREATE TABLE baseball_player (
    person_id integer PRIMARY KEY,
    position  text    NOT NULL,
    FOREIGN KEY (person_id) REFERENCES person(id) ON UPDATE CASCADE ON DELETE SET DEFAULT
);
EOF

$db->dbh->do($sql_baseball_player);
$db->dbh->do('CREATE INDEX ON baseball_player (position)');

my $pg_dump_result = undef;
eval { $pg_dump_result = desc_by_pg_dump($db, 'person'); };
if ( $@ || !defined $pg_dump_result ) {
    plan skip_all => "pg_dump can't run correctly";
}

subtest 'desc - table does not exist', sub {
    my $result = $db->desc('hoge');
    is( $result, undef );
};

subtest 'desc person - basic syntax, null/notnull, serial', sub {
    my $expected = desc_by_pg_dump($db, 'person');
    note $expected;
    my $result = $db->desc('person');
    eq_or_diff( $result, $expected );
};

subtest 'desc detective - foreign key(SET NULL, RESTRICT), index', sub {
    my $expected = desc_by_pg_dump($db, 'detective');
    note $expected;
    my $result = $db->desc('detective');
    eq_or_diff( $result, $expected );

};

subtest 'desc baseball_player - foreign key(SET DEFAULT, CASCADE), reserved word, index', sub {
    my $expected = desc_by_pg_dump($db, 'baseball_player');
    note $expected;
    my $result = $db->desc('baseball_player');
    eq_or_diff( $result, $expected );

};


done_testing;
