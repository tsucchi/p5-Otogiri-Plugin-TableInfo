[![Build Status](https://travis-ci.org/tsucchi/p5-Otogiri-Plugin-TableInfo.png?branch=master)](https://travis-ci.org/tsucchi/p5-Otogiri-Plugin-TableInfo) [![Coverage Status](https://coveralls.io/repos/tsucchi/p5-Otogiri-Plugin-TableInfo/badge.png?branch=master)](https://coveralls.io/r/tsucchi/p5-Otogiri-Plugin-TableInfo?branch=master)
# NAME

Otogiri::Plugin::TableInfo - retrieve table information from database

# SYNOPSIS

    use Otogiri::Plugin::TableInfo;
    my $db = Otogiri->new( connect_info => [ ... ] );
    $db->load_plugin('TableInfo');
    my @table_names = $db->show_tables();

# DESCRIPTION

Otogiri::Plugin::TableInfo is Otogiri plugin to fetch table information from database.

# METHODS

## my @table\_names = $self->show\_tables(\[$like\_regex\]);

returns table names in database.

parameter `$like_regex` is optional. If it is passed, table name is filtered by regex like MySQL's `SHOW TABLES LIKE ...` statement.

    my @table_names = $db->show_tables(qr/^user_/); # return table names that starts with 'user_'

If `$like_regex` is not passed, all table\_names in current database are returned.

# LICENSE

Copyright (C) Takuya Tsuchida.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Takuya Tsuchida <tsucchi@cpan.org>
