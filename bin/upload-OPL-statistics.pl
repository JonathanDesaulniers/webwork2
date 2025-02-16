#!/usr/bin/perl

##############################################################################
# WeBWorK Online Homework Delivery System
# Copyright &copy; 2000-2018 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/bin/wwdb,v 1.13 2006/01/25 23:13:45 sh002i Exp $
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

# This script dumps the local OPL statistics table and uploads it.

my $pg_dir;
BEGIN {
	die "WEBWORK_ROOT not found in environment.\n" unless exists $ENV{WEBWORK_ROOT};
	$pg_dir = $ENV{PG_ROOT} // "$ENV{WEBWORK_ROOT}/../pg";
	die "The pg directory must be defined in PG_ROOT" unless (-e $pg_dir);
}
use lib "$ENV{WEBWORK_ROOT}/lib";
use lib "$pg_dir/lib";

use WeBWorK::CourseEnvironment;

use Net::Domain;
use String::ShellQuote;

my $ce = new WeBWorK::CourseEnvironment({
	webwork_dir => $ENV{WEBWORK_ROOT},
	});

# Get DB connection settings

my $db     = $ce->{database_name};
my $host   = $ce->{database_host};
my $port   = $ce->{database_port};
my $dbuser = $ce->{database_username};
my $dbpass = $ce->{database_password};

my $domainname = Net::Domain::domainname;
my $time = time();
my $output_file = "$domainname-$time-opl.sql";

print "Dumping local OPL statistics\n";

$dbuser = shell_quote($dbuser);
$db = shell_quote($db);

$ENV{'MYSQL_PWD'}=$dbpass;

my $mysqldump_command = $ce->{externalPrograms}->{mysqldump};

# Conditionally add --column-statistics=0 as MariaDB databases do not support it
# see: https://serverfault.com/questions/912162/mysqldump-throws-unknown-table-column-statistics-in-information-schema-1109
#      https://github.com/drush-ops/drush/issues/4410

my $column_statistics_off = "";
my $test_for_column_statistics = `$mysqldump_command --help | grep 'column-statistics'`;
if ( $test_for_column_statistics ) {
  $column_statistics_off = " --column-statistics=0 ";
}

`$mysqldump_command --host=$host --port=$port --user=$dbuser $column_statistics_off $db OPL_local_statistics > $output_file`;

print "Database File Created\n";

my $done;
my $desc;
my $input;

do {

  print "\nWe would appreciate it if you could provide \nsome basic information to help us \nkeep track of the data we receive.\n\n";

  $desc  = "File:\n$output_file\n";

  print "What university is this data for?\n";

  $desc .=  "University:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "What department is this data for?\n";

  $desc .=  "Department:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "What is your name?\n";

  $desc .=  "Name:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "What is your email address?\n";

  $desc .=  "Email:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "Have you uploaded data from this server before?\n";

  $desc .=  "Uploaded Previously:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "Approximately what years does this data span?\n";

  $desc .=  "Years:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "Approximately how many classes are included?\n";

  $desc .=  "Number of Classes:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "Additional Comments?\n";

  $desc .=  "Additional Comments:\n";
  $input = <STDIN>;
  $desc .=  $input;

  print "The data you just entered is below:\n\n";

  print $desc."\n";

  my $answered;

  do {
    print "Please choose one of the following:\n";
    print "1. Upload Data\n";
    print "2. Reenter above information.\n";
    print "3. Cancel.\n";
    print "[1/2/3]? ";

    $input = <STDIN>;
    chomp $input;

    if ($input eq '3') {
      exit;
    } elsif ($input eq '2') {
      $done = 0;
      $answered = 1;
    } elsif ($input eq '1') {
      $done = 1;
      $answered = 1;
    } else {
      $answered = 0;
    }

  } while (!$answered);


} while (!$done);

my $desc_file = "$domainname-$time-desc.txt";

open(my $fh, ">", $desc_file)
  or die "Couldn't open file for saving description.";

print $fh $desc;

close($fh);

my $tar_file = "$domainname-$time-data.tar.gz";

print "Zipping files\n";
`tar -czf $tar_file $output_file $desc_file`;

print "Uploading file\n";

`echo "put $tar_file" | sftp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPort=57281 wwdata\@52.88.32.79`;


1;
