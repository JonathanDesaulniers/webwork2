################################################################################
# WeBWorK Online Homework Delivery System
# Copyright &copy; 2000-2022 The WeBWorK Project, https://github.com/openwebwork
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::DB::Record::PastAnswer;
use base WeBWorK::DB::Record;

=head1 NAME

WeBWorK::DB::Record::PastAnswers - Represents a past answer

=cut

use strict;
use warnings;

BEGIN {
	__PACKAGE__->_fields(

		answer_id      => { type => "INT AUTO_INCREMENT",    key => 1 },
		course_id      => { type => "VARCHAR(40) NOT NULL",  key => 1 },
		user_id        => { type => "VARCHAR(100) NOT NULL", key => 1 },
		set_id         => { type => "VARCHAR(100) NOT NULL", key => 1 },
		problem_id     => { type => "INT NOT NULL",          key => 1 },
		source_file    => { type => "TEXT" },
		timestamp      => { type => "INT" },
		scores         => { type => "TINYTEXT" },
		answer_string  => { type => "VARCHAR(5012)" },
		comment_string => { type => "VARCHAR(5012)" },

	);
}

1;
