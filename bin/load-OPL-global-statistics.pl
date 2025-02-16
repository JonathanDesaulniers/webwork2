#!/usr/bin/perl

##############################################################################
# WeBWorK Online Homework Delivery System
# Copyright &copy; 2000-2019 The WeBWorK Project, http://openwebwork.sf.net/
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See either the GNU General Public License or the
# Artistic License for more details.
##############################################################################

# This script loads the OPL global statistics, which is often done by bin/update-OPL-statistics but may need to be done outside of that setting.
use strict;

# Get the necessary packages, including adding webwork to our path.

my $pg_dir;
BEGIN {
	die "WEBWORK_ROOT not found in environment.\n" unless exists $ENV{WEBWORK_ROOT};
	$pg_dir = $ENV{PG_ROOT} // "$ENV{WEBWORK_ROOT}/../pg";
	die "The pg directory must be defined in PG_ROOT" unless (-e $pg_dir);
}

use lib "$ENV{WEBWORK_ROOT}/lib";
use lib "$pg_dir/lib";

use WeBWorK::CourseEnvironment;

use String::ShellQuote;
use DBI;

# get course environment and configured OPL path

my $ce = new WeBWorK::CourseEnvironment({
	webwork_dir => $ENV{WEBWORK_ROOT},
	});

my $dbh = DBI->connect(
        $ce->{problemLibrary_db}->{dbsource},
        $ce->{problemLibrary_db}->{user},
        $ce->{problemLibrary_db}->{passwd},
        {
		AutoCommit => 0,
                PrintError => 0,
                RaiseError => 1,
        },
);

# check to see if the global statistics file exists and if it does, upload it.

my $global_sql_file = $ce->{problemLibrary}{root}.'/OPL_global_statistics.sql';

if (-e $global_sql_file) {

  my $db     = $ce->{database_name};
  my $host   = $ce->{database_host};
  my $port   = $ce->{database_port};
  my $dbuser = $ce->{database_username};
  my $dbpass = $ce->{database_password};

  $dbh->do(<<EOS);
DROP TABLE IF EXISTS OPL_global_statistics;
EOS
  $dbh->commit();

  $dbuser = shell_quote($dbuser);
  $db = shell_quote($db);

  $ENV{'MYSQL_PWD'}=$dbpass;

  my $mysql_command = $ce->{externalPrograms}->{mysql};

  `$mysql_command --host=$host --port=$port --user=$dbuser $db < $global_sql_file`;

}

1;
