use strict;
use warnings;

# PostgreSQL DDL compare tool between pg_dump and O::P::TableInfo->desc()
#
# usage: 
# cp eg/config.pl.sample eg/config.pl
# vi eg/config.pl
# ...(edit config to connect your DB)
# prove -l eg/compare.t


use Test::More;
use List::MoreUtils qw(any);
use Test::Differences;
unified_diff;

use Otogiri;
use Otogiri::Plugin;
Otogiri->load_plugin('TableInfo');

my $config = do("eg/config.pl") or die "can't read config: $!";

my $db = Otogiri->new( connect_info => $config->{connect_info} );

for my $table_name ( $db->show_tables() ) {
    next if ( any{ $table_name eq $_ } @{ $config->{exclude_tables} || [] } );

    $db->use_pg_dump(1);
    my $pg_dump = $db->desc($table_name);
    $db->use_pg_dump(0);
    my $inspector = $db->desc($table_name);
    eq_or_diff($pg_dump, $inspector) or fail "error in $table_name";
}

done_testing;
