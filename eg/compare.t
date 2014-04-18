use strict;
use warnings;

# PostgreSQL DDL compare tool between pg_dump and O::P::TableInfo->desc()
#
# usage: 
# cp eg/config.pl.sample eg/config.pl
# vi eg/config.pl
# ...(edit config to connect your DB)
# prove -l eg/compare.t
#
# NOTE: to set password for pg_dump, use .pgpass file

use Test::More;
use List::MoreUtils qw(any);
use DBI;
use Test::Differences;
unified_diff;

use Otogiri;
use Otogiri::Plugin;
Otogiri->load_plugin('TableInfo');

my $config = do("eg/config.pl") or die "can't read config: $!";

my $db = Otogiri->new( connect_info => $config->{connect_info} );

for my $table_name ( $db->show_tables() ) {
    next if ( any{ $table_name eq $_ } @{ $config->{exclude_tables} || [] } );

    my $pg_dump = desc_by_pg_dump($db, $table_name);
    my $inspector = $db->desc($table_name);
    eq_or_diff($pg_dump, $inspector) or fail "error in $table_name";
}

done_testing;

sub desc_by_pg_dump {
    my ($db, $table_name) = @_;

    my ($dsn, $user, $pass) = @{ $db->connect_info };
    my ($scheme, $driver, $attr_string, $attr_hash, $driver_dsn) = DBI->parse_dsn($dsn);
    my %attr = _parse_driver_dsn($driver_dsn);
    $attr{user}     = $user if ( !exists $attr{user} );
    $attr{password} = $pass if ( !exists $attr{password} );
    my $cmd = _build_pg_dump_command($table_name, %attr);
    my $result = `$cmd`;
    return _trim_result($result);
}

sub _parse_driver_dsn {
    my ($driver_dsn) = @_;

    my @statements = split(qr/;/, $driver_dsn);
    my %result = ();
    for my $statement ( @statements ) {
        my ($variable_name, $value) = map{ _trim($_) } split(qr/=/, $statement);
        $result{$variable_name} = $value;
    }
    return %result;
}

sub _build_pg_dump_command {
    my ($table_name, %args) = @_;
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
    my ($input) = @_;
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
    my ($string) = @_;
    $string =~ s/\A\s+//;
    $string =~ s/\s+\z//;
    return $string;
}
