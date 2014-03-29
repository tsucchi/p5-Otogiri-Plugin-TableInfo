use strict;
use warnings;
use Test::More;
use DBI;
use Otogiri;
use Otogiri::Plugin;
use Test::PostgreSQL;

my $pg = Test::PostgreSQL->new(
    my_cnf => {
        'skip-networking' => '',
    }
) or plan skip_all => $Test::PostgreSQL::errstr;

Otogiri->load_plugin('TableInfo');

my $db = Otogiri->new( connect_info => [$pg->dsn(dbname => 'test'), '', '', { RaiseError => 1, PrintError => 0 }] );
my $sql = <<'EOF';
CREATE TABLE member (
    id   SERIAL  PRIMARY KEY,
    name TEXT    NOT NULL
);
EOF

$db->dbh->do($sql);


subtest 'desc', sub {
    # どんな感じになるのかまだ分からない...
    my $expected = <<EOSQL;
CREATE TABLE `member` (
  `id` integer NOT NULL,
  `name` text NOT NULL,
  PRIMARY KEY (`id`)
)
EOSQL
    $expected =~ s/\n$//; #trim last newline
    my $result = $db->desc('member');
    #warn $result;

 TODO: {
        local $TODO = 'どんな感じに出せば良いかまだ分からん';
        is( $result, $expected );
    }
};

subtest 'desc(table does not exist)', sub {
    my $result = $db->desc('hoge');
    is( $result, undef );
};





done_testing;
