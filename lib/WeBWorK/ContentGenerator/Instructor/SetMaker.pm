################################################################################
# WeBWorK Online Homework Delivery System
# Copyright &copy; 2000-2021 The WeBWorK Project, https://github.com/openwebwork
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.	 See either the GNU General Public License or the
# Artistic License for more details.
################################################################################


package WeBWorK::ContentGenerator::Instructor::SetMaker;
use base qw(WeBWorK::ContentGenerator::Instructor);

=head1 NAME

WeBWorK::ContentGenerator::Instructor::SetMaker - Make homework sets.

=cut

use strict;
use warnings;


#use CGI qw(-nosticky);
use WeBWorK::CGI;
use WeBWorK::Debug;
use WeBWorK::Form;
use WeBWorK::Utils qw(readDirectory max sortByName wwRound x);
use WeBWorK::Utils::Tasks qw(renderProblems);
use WeBWorK::Utils::Tags;
use WeBWorK::Utils::LibraryStats;
use WeBWorK::Utils::LanguageAndDirection;
use File::Find;
use MIME::Base64 qw(encode_base64);
use Encode;

require WeBWorK::Utils::ListingDB;

# we use x to mark strings for maketext
use constant SHOW_HINTS_DEFAULT => 0;
use constant SHOW_SOLUTIONS_DEFAULT => 0;
use constant MAX_SHOW_DEFAULT => 20;
use constant NO_LOCAL_SET_STRING => x('No sets in this course yet');
use constant SELECT_SET_STRING => x('Select a Set from this Course');
use constant SELECT_LOCAL_STRING => x('Select a Problem Collection');
use constant MY_PROBLEMS => x('My Problems');
use constant MAIN_PROBLEMS => x('Unclassified Problems');
use constant ALL_CHAPTERS => 'All Chapters';
use constant ALL_SUBJECTS => 'All Subjects';
use constant ALL_SECTIONS => 'All Sections';
use constant ALL_TEXTBOOKS => 'All Textbooks';

use constant LIB2_DATA => {
  'dbchapter' => {name => 'library_chapters', all => 'All Chapters'},
  'dbsection' =>  {name => 'library_sections', all =>'All Sections' },
  'dbsubject' =>  {name => 'library_subjects', all => 'All Subjects' },
  'textbook' =>  {name => 'library_textbook', all =>  'All Textbooks'},
  'textchapter' => {name => 'library_textchapter', all => 'All Chapters'},
  'textsection' => {name => 'library_textsection', all => 'All Sections'},
  'keywords' =>  {name => 'library_keywords', all => '' },
  };

## Flags for operations on files

use constant ADDED => 1;
use constant HIDDEN => (1 << 1);
use constant SUCCESS => (1 << 2);

##	for additional problib buttons
my %problib;	## This is configured in defaults.config
my %ignoredir = (
	'.' => 1, '..' => 1, 'CVS' => 1, 'tmpEdit' => 1,
	'headers' => 1, 'macros' => 1, 'email' => 1, 'graphics'=>1, '.svn' => 1, 'achievements' => 1,
);

sub prepare_activity_entry {
	my $self=shift;
	my $r = $self->r;
	my $user = $self->r->param('user') || 'NO_USER';
	return("In SetMaker as user $user");
}

## This is for searching the disk for directories containing pg files.
## to make the recursion work, this returns an array where the first
## item is the number of pg files in the directory.  The second is a
## list of directories which contain pg files.
##
## If a directory contains only one pg file and the directory name
## is the same as the file name, then the directory is considered
## to be part of the parent directory (it is probably in a separate
## directory only because it has auxiliary files that want to be
## kept together with the pg file).
##
## If a directory has a file named "=library-ignore", it is never
## included in the directory menu.  If a directory contains a file
## called "=library-combine-up", then its pg are included with those
## in the parent directory (and the directory does not appear in the
## menu).  If it has a file called "=library-no-combine" then it is
## always listed as a separate directory even if it contains only one
## pg file.

sub get_library_sets {
	my $top = shift; my $dir = shift;
	# ignore directories that give us an error
	my @lis = eval { readDirectory($dir) };
	if ($@) {
		warn $@;
		return (0);
	}
	return (0) if grep /^=library-ignore$/, @lis;

	my @pgfiles = grep { m/\.pg$/ and (not m/(Header|-text)(File)?\.pg$/) and -f "$dir/$_"} @lis;
	my $pgcount = scalar(@pgfiles);
	my $pgname = $dir; $pgname =~ s!.*/!!; $pgname .= '.pg';
	my $combineUp = ($pgcount == 1 && $pgname eq $pgfiles[0] && !(grep /^=library-no-combine$/, @lis));

	my @pgdirs;
	my @dirs = grep {!$ignoredir{$_} and -d "$dir/$_"} @lis;
	if ($top == 1) {@dirs = grep {!$problib{$_}} @dirs}
	# Never include Library at the top level
	if ($top == 1) {@dirs = grep {$_ ne 'Library'} @dirs}
	foreach my $subdir (@dirs) {
		my @results = get_library_sets(0, "$dir/$subdir");
		$pgcount += shift @results; push(@pgdirs,@results);
	}

	return ($pgcount, @pgdirs) if $top || $combineUp || grep /^=library-combine-up$/, @lis;
	return (0,@pgdirs,$dir);
}

sub get_library_pgs {
	my $top = shift; my $base = shift; my $dir = shift;
	my @lis = readDirectory("$base/$dir");
	return () if grep /^=library-ignore$/, @lis;
	return () if !$top && grep /^=library-no-combine$/, @lis;

	my @pgs = grep { m/\.pg$/ and (not m/(Header|-text)\.pg$/) and -f "$base/$dir/$_"} @lis;
	my $others = scalar(grep { (!m/\.pg$/ || m/(Header|-text)\.pg$/) &&
	                            !m/(\.(tmp|bak)|~)$/ && -f "$base/$dir/$_" } @lis);

	my @dirs = grep {!$ignoredir{$_} and -d "$base/$dir/$_"} @lis;
	if ($top == 1) {@dirs = grep {!$problib{$_}} @dirs}
	foreach my $subdir (@dirs) {push(@pgs, get_library_pgs(0,"$base/$dir",$subdir))}

	return () unless $top || (scalar(@pgs) == 1 && $others) || grep /^=library-combine-up$/, @lis;
	return (map {"$dir/$_"} @pgs);
}

sub list_pg_files {
	my ($templates,$dir) = @_;
	my $top = ($dir eq '.')? 1 : 2;
	my @pgs = get_library_pgs($top,$templates,$dir);
	return sortByName(undef,@pgs);
}

## Search for set definition files

sub get_set_defs {
	my $topdir = shift;
	my @found_set_defs;
	# get_set_defs_wanted is a closure over @found_set_defs
	my $get_set_defs_wanted = sub {
		#my $fn = $_;
		#my $fdir = $File::Find::dir;
		#return() if($fn !~ /^set.*\.def$/);
		##return() if(not -T $fn);
		#push @found_set_defs, "$fdir/$fn";
		push @found_set_defs, $_ if m|/set[^/]*\.def$|;
	};
	find({ wanted => $get_set_defs_wanted, follow_fast=>1, no_chdir=>1}, $topdir);
	map { $_ =~ s|^$topdir/?|| } @found_set_defs;
	return @found_set_defs;
}

## Try to make reading of set defs more flexible.  Additional strategies
## for fixing a path can be added here.

sub munge_pg_file_path {
	my $self = shift;
	my $pg_path = shift;
	my $path_to_set_def = shift;
	my $end_path = $pg_path;
	# if the path is ok, don't fix it
	return($pg_path) if(-e $self->r->ce->{courseDirs}{templates}."/$pg_path");
	# if we have followed a link into a self contained course to get
	# to the set.def file, we need to insert the start of the path to
	# the set.def file
	$end_path = "$path_to_set_def/$pg_path";
	return($end_path) if(-e $self->r->ce->{courseDirs}{templates}."/$end_path");
	# if we got this far, this path is bad, but we let it produce
	# an error so the user knows there is a troublesome path in the
	# set.def file.
	return($pg_path);
}

## Problems straight from the OPL database come with MO and static
## tag information.  This is for other times, like next/prev page.

sub getDBextras {
	my $r = shift;
	my $sourceFileName = shift;

	if($sourceFileName =~ /^Library/) {
		return @{WeBWorK::Utils::ListingDB::getDBextras($r, $sourceFileName)};
	}

	my $filePath = $r->ce->{courseDirs}{templates}."/$sourceFileName";
	my $tag_obj = WeBWorK::Utils::Tags->new($filePath);
	my $isMO = $tag_obj->{MO} || 0;
	my $isstatic = $tag_obj->{Static} || 0;

	return ($isMO, $isstatic);
}

## With MLT, problems come in groups, so we need to find next/prev
## problems.  Return index, or -1 if there are no more.
sub next_prob_group {
	my $ind = shift;
	my @pgfiles = @_;
	my $len = scalar(@pgfiles);
	return -1 if($ind >= $len-1);
	my $mlt= $pgfiles[$ind]->{morelt} || 0;
	return $ind+1 if($mlt == 0);
	while($ind<$len and defined($pgfiles[$ind]->{morelt}) and $pgfiles[$ind]->{morelt} == $mlt) {
		$ind++;
	}
	return -1 if($ind==$len);
	return $ind;
}

sub prev_prob_group {
	my $ind = shift;
	my @pgfiles = @_;
	return -1 if $ind==0;
	$ind--;
	my $mlt = $pgfiles[$ind]->{morelt};
	return $ind if $mlt==0;
	# We have to search to the beginning of this group
	while($ind>=0 and $mlt == $pgfiles[$ind]->{morelt}) {
		$ind--;
	}
	return($ind+1);
}

sub end_prob_group {
	my $ind = shift;
	my @pgfiles = @_;
	my $next = next_prob_group($ind, @pgfiles);
	return( ($next==-1) ? $#pgfiles : $next-1);
}

## Read a set definition file.  This could be abstracted since it happens
## elsewhere.  Here we don't have to process so much of the file.

sub read_set_def {
	my $self = shift;
	my $r = $self->r;
	my $filePathOrig = shift;
	my $filePath = $r->ce->{courseDirs}{templates}."/$filePathOrig";
	$filePathOrig =~ s/set.*\.def$//;
	$filePathOrig =~ s|/$||;
	$filePathOrig = "." if ($filePathOrig !~ /\S/);
	my @pg_files = ();
	my ($line, $got_to_pgs, $name, @rest) = ("", 0, "");
	if ( open (SETFILENAME, "$filePath") )    {
	    while($line = <SETFILENAME>) {
		chomp($line);
		$line =~ s|(#.*)||; # don't read past comments
		if($got_to_pgs == 1) {
		    unless ($line =~ /\S/) {next;} # skip blank lines
		    ($name,@rest) = split (/\s*,\s*/,$line);
		    $name =~ s/\s*//g;
		    push @pg_files, $name;
		} elsif ($got_to_pgs == 2) {
		    # skip lines which dont identify source files
		    unless ($line =~ /source_file\s*=\s*(\S+)/) {
			next;
		    }
		    # otherwise we got the name from the regexp
		    push @pg_files, $1;
		} else {
		    $got_to_pgs = 1 if ($line =~ /problemList\s*=/);
		    $got_to_pgs = 2 if ($line =~ /problemListV2/);
		}
	    }
	} else {
	    $self->addbadmessage($r->maketext("Cannot open [_1]",$filePath));
	}
	# This is where we would potentially munge the pg file paths
	# One possibility
	@pg_files = map { $self->munge_pg_file_path($_, $filePathOrig) } @pg_files;
	return(@pg_files);
}

## go through past page getting a list of identifiers for the problems
## and whether or not they are selected, and whether or not they should
## be hidden

sub get_past_problem_files {
	my $r = shift;
	my @found=();
	my $count =1;
	while (defined($r->param("filetrial$count"))) {
		my $val = 0;
		$val |= ADDED if($r->param("trial$count"));
		$val |= HIDDEN if($r->param("hideme$count"));
		push @found, [$r->param("filetrial$count"), $val];
		$count++;
	}
	return(\@found);
}

#### For adding new problems

sub add_selected {
	my $self = shift;
	my $db = shift;
	my $setName = shift;
	my @past_problems = @{$self->{past_problems}};
	my @selected = @past_problems;
	my (@path, $file, $selected, $freeProblemID);

	my $addedcount=0;

	for $selected (@selected) {
		if($selected->[1] & ADDED) {
			$file = $selected->[0];
			my $problemRecord = $self->addProblemToSet(setName => $setName,
				sourceFile => $file);
			$freeProblemID++;
			$self->assignProblemToAllSetUsers($problemRecord);
			$selected->[1] |= SUCCESS;
			$addedcount++;
		}
	}
	return($addedcount);
}


############# List of sets of problems in templates directory

sub get_problem_directories {
        my $r = shift;
        my $ce = $r->ce;
	my $lib = shift;
	my $source = $ce->{courseDirs}{templates};
	my $main = $r->maketext(MY_PROBLEMS); my $isTop = 1;
	if ($lib) {$source .= "/$lib"; $main = $r->maketext(MAIN_PROBLEMS); $isTop = 2}
	my @all_problem_directories = get_library_sets($isTop, $source);
	my $includetop = shift @all_problem_directories;
	my $j;
	for ($j=0; $j<scalar(@all_problem_directories); $j++) {
		$all_problem_directories[$j] =~ s|^$ce->{courseDirs}->{templates}/?||;
	}
	@all_problem_directories = sortByName(undef, @all_problem_directories);
	unshift @all_problem_directories, $main if($includetop);
	return (\@all_problem_directories);
}

# All of the browsing panel versions have a view problems line. Abstract it.
sub view_problems_line {
	my $internal_name = shift;
	my $label         = shift;
	my $r             = shift;    # so we can get parameter values

	my $result = CGI::start_div({ class => 'd-flex flex-wrap justify-content-center' });

	$result .= CGI::submit({ name => $internal_name, value => $label, class => 'btn btn-secondary btn-sm mb-2' });

	# Give a choice of display modes.
	my %display_modes = %{ WeBWorK::PG::DISPLAY_MODES() };
	my @active_modes  = grep { exists $display_modes{$_} } @{ $r->ce->{pg}{displayModes} };
	push @active_modes, 'None';

	# We have our own displayMode since its value may be None, which is illegal in other modules.
	my $mydisplayMode = $r->param('mydisplayMode') || $r->ce->{pg}->{options}->{displayMode};
	$result .= CGI::div(
		{ class => 'd-inline-block ms-2 mb-2' },
		CGI::label(
			{ for => 'mydisplayMode', class => 'col-form-label col-form-label-sm' },
			$r->maketext('Display Mode:')
		),
		CGI::popup_menu({
			name    => 'mydisplayMode',
			id      => 'mydisplayMode',
			values  => \@active_modes,
			default => $mydisplayMode,
			class   => 'form-select form-select-sm d-inline w-auto'
		}),
		CGI::hidden({ name => "original_displayMode", default => $mydisplayMode })
	);

	# Now we give a choice of the number of problems to show.
	$result .= CGI::div(
		{ class => 'd-inline-block ms-2 mb-2' },
		CGI::label({ for => 'max_shown', class => 'col-form-label col-form-label-sm' }, $r->maketext('Max. Shown:')),
		CGI::popup_menu({
			name    => 'max_shown',
			id      => 'max_shown',
			values  => [ 5, 10, 15, 20, 25, 30, 50, 'All' ],
			default => $r->param('max_shown') || MAX_SHOW_DEFAULT,
			class   => 'form-select form-select-sm d-inline w-auto'
		})
	);

	# Option of whether to show hints and solutions
	$result .= CGI::div(
		{ class => 'd-inline-block ms-2 mb-2' },
		CGI::div(
			{ class => 'form-check form-check-inline ms-2' },
			CGI::checkbox({
				name            => "showHints",
				checked         => $r->param('showHints') || SHOW_HINTS_DEFAULT,
				label           => $r->maketext("Hints"),
				class           => 'form-check-input me-1',
				labelattributes => { class => 'form-check-label col-form-label-sm' }
			})
		),
		CGI::div(
			{ class => 'form-check form-check-inline ms-2' },
			CGI::checkbox({
				name            => "showSolutions",
				checked         => $r->param('showSolutions') || SHOW_SOLUTIONS_DEFAULT,
				label           => $r->maketext("Solutions"),
				class           => 'form-check-input me-1',
				labelattributes => { class => 'form-check-label col-form-label-sm' }
			})
		)
	);

	$result .= CGI::end_div();

	return $result;
}

# The browsing panel has three versions.
# Version 1 is local problems
sub browse_local_panel {
	my $self = shift;
	my $r = $self->r;
	my $library_selected = shift;
	my $lib = shift || ''; $lib =~ s/^browse_//;
	my $name = ($lib eq '')? $r->maketext('Local') : Encode::decode("UTF-8",$problib{$lib});

	my $list_of_prob_dirs= get_problem_directories($r,$lib);
	if(scalar(@$list_of_prob_dirs) == 0) {
		$library_selected = $r->maketext("Found no directories containing problems");
		unshift @{$list_of_prob_dirs}, $library_selected;
	} else {
		my $default_value = $r->maketext(SELECT_LOCAL_STRING);
		if (!defined $library_selected or $library_selected eq $default_value) {
			unshift @{$list_of_prob_dirs},	$default_value;
			$library_selected = $default_value;
		}
	}
	debug("library is $lib and sets are $library_selected");

	my $popup_menu_args = {
		name    => 'library_sets',
		id      => 'library_sets',
		values  => $list_of_prob_dirs,
		default => $library_selected,
		class   => 'form-select form-select-sm d-inline w-auto'
	};

	# Make labels without the $lib prefix.  This reduces the width of the popup menu.
	if (length($lib)) {
		$popup_menu_args->{labels} = { map { my ($l) = $_ =~ /^$lib\/(.*)$/; $_ => $l } @$list_of_prob_dirs };
	}

	print CGI::div(
		{ class => "InfoPanel" },
		CGI::div(
			{ class => 'mb-2' },
			CGI::label({ for => 'library_sets', class => 'col-form-label-sm' }, $r->maketext("[_1] Problems:", $name)),
			CGI::popup_menu($popup_menu_args)
		),
		view_problems_line('view_local_set', $r->maketext('View Problems'), $self->r),
	);
}

# Version 2 is local homework sets
sub browse_mysets_panel {
	my $self = shift;
	my $r = $self->r;
	my $library_selected = shift;
	my $list_of_local_sets = shift;
	my $default_value = $r->maketext("Select a Homework Set");

	if(scalar(@$list_of_local_sets) == 0) {
		$list_of_local_sets = [$r->maketext(NO_LOCAL_SET_STRING)];
	} elsif (!defined $library_selected or $library_selected eq $default_value) {
		unshift @{$list_of_local_sets},	 $default_value;
		$library_selected = $default_value;
	}

	print CGI::div(
		{ class => "InfoPanel" },
		CGI::div(
			{ class => 'mb-2' },
			CGI::label({ for => 'library_sets', class => 'col-form-label-sm' }, $r->maketext("Browse from:")),
			CGI::popup_menu({
				name    => 'library_sets',
				id      => 'library_sets',
				values  => $list_of_local_sets,
				default => $library_selected,
				class   => 'form-select form-select-sm d-inline w-auto'
			})
		),
		view_problems_line('view_mysets_set', $r->maketext('View Problems'), $self->r)
	);
}

# Version 3 is the problem library
# This comes in 3 forms: problem library version 1, problem library version 2 basic, and problem library version 2
# advanced.  This function checks what we are supposed to do, or aborts if the problem library has not been installed.

sub browse_library_panel {
	my $self = shift;
	my $r    = $self->r;
	my $ce   = $r->ce;

	# See if the problem library is installed
	my $libraryRoot = $r->{ce}{problemLibrary}{root};

	unless ($libraryRoot) {
		print CGI::div(
			{ class => 'alert alert-danger p-1 mb-2', align => "center" },
			"The problem library has not been installed."
		);
		return;
	}
	# Test if the Library directory link exists.  If not, try to make it
	unless (-d "$ce->{courseDirs}{templates}/Library") {
		unless (symlink($libraryRoot, "$ce->{courseDirs}{templates}/Library")) {
			my $msg = <<"HERE";
You are missing the directory <code>templates/Library</code>, which is needed
for the Problem Library to function.	It should be a link pointing to
<code>$libraryRoot</code>, which you set in <code>conf/site.conf</code>.
I tried to make the link for you, but that failed.	Check the permissions
in your <code>templates</code> directory.
HERE
			$self->addbadmessage($msg);
		}
	}

	# Now check what version we are supposed to use
	my $libraryVersion = $r->{ce}{problemLibrary}{version} || 2;
	if ($libraryVersion == 1) {
		#return $self->browse_library_panel1;
		print CGI::div(
			{ class => 'alert alert-danger p-1 mb-2', align => "center" },
			"Problem library version 1 is no longer supported."
		);
		return;
	} elsif ($libraryVersion >= 2) {
		return $self->browse_library_panel2 if ($self->{library_basic} == 1);
		return $self->browse_library_panel2adv;
	} else {
		print CGI::div(
			{ class => 'alert alert-danger p-1 mb-2', align => "center" },
			"The problem library version is set to an illegal value."
		);
		return;
	}
}

# FIXME:  This needs to be deleted.  The methods called here are commented out in WeBWorK::Utils::ListingDB.
sub browse_library_panel1 {
	my $self = shift;
	my $r = $self->r;
	my $ce = $r->ce;

	my @chaps = WeBWorK::Utils::ListingDB::getAllChapters($r->{ce});
	unshift @chaps, LIB2_DATA->{dbchapter}{all};
	my $chapter_selected = $r->param('library_chapters') || LIB2_DATA->{dbchapter}->{all};

	my @sects=();
	if ($chapter_selected ne LIB2_DATA->{dbchapter}{all}) {
		@sects = WeBWorK::Utils::ListingDB::getAllSections($r->{ce}, $chapter_selected);
	}

	unshift @sects, ALL_SECTIONS;
	my $section_selected =	$r->param('library_sections') || LIB2_DATA->{dbsection}{all};

	my $view_problem_line = view_problems_line('lib_view', $r->maketext('View Problems'), $self->r);

	print CGI::Tr(CGI::td({-class=>"InfoPanel"},
		CGI::start_table(),
			CGI::Tr({},
				CGI::td([$r->maketext("Chapter:"),
					CGI::popup_menu(-name=> 'library_chapters',
					                -values=>\@chaps,
					                -default=> $chapter_selected
					),
					CGI::submit({
						name => "lib_select_chapter",
						value => "Update Section List",
						class => 'btn btn-secondary btn-sm'
					})
				])),
			CGI::Tr({},
				CGI::td($r->maketext("Section:")),
				CGI::td({-colspan=>2},
					CGI::popup_menu(-name=> 'library_sections',
					                -values=>\@sects,
					                -default=> $section_selected
			))),

			CGI::Tr(CGI::td({-colspan=>3}, $view_problem_line)),
			CGI::end_table(),
		));
}

sub browse_library_panel2 {
	my $self = shift;
	my $r    = $self->r;

	my @subjs = WeBWorK::Utils::ListingDB::getAllDBsubjects($r);
	unshift @subjs, LIB2_DATA->{dbsubject}{all};

	my @chaps = WeBWorK::Utils::ListingDB::getAllDBchapters($r);
	unshift @chaps, LIB2_DATA->{dbchapter}{all};

	my @sects = ();
	@sects = WeBWorK::Utils::ListingDB::getAllDBsections($r);
	unshift @sects, LIB2_DATA->{dbsection}{all};

	my $count_line = WeBWorK::Utils::ListingDB::countDBListings($r);
	if ($count_line == 0) {
		$count_line = $r->maketext("There are no matching WeBWorK problems");
	} else {
		$count_line = $r->maketext("There are [_1] matching WeBWorK problems", $count_line);
	}

	print CGI::div(
		CGI::hidden({ name => 'library_is_basic', default => 1, override => 1 }),
		CGI::div(
			{ class => 'row mb-2' },
			CGI::div({ class => 'col-md-3' }, ''),
			CGI::div(
				{ class => 'col-md-6 col-sm-8' },
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_subjects', class => 'col-2 col-form-label col-form-label-sm' },
						$r->maketext('Subject:')
					),
					CGI::div(
						{ class => 'col-10' },
						CGI::popup_menu({
							name    => 'library_subjects',
							id      => 'library_subjects',
							values  => \@subjs,
							default => $r->param('library_subjects') || LIB2_DATA->{dbsubject}{all},
							class   => 'form-select form-select-sm'
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_chapters', class => 'col-2 col-form-label col-form-label-sm' },
						$r->maketext('Chapter:')
					),
					CGI::div(
						{ class => 'col-10' },
						CGI::popup_menu({
							name    => 'library_chapters',
							id      => 'library_chapters',
							values  => \@chaps,
							default => $r->param('library_chapters') || LIB2_DATA->{dbchapter}{all},
							class   => 'form-select form-select-sm'
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_sections', class => 'col-2 col-form-label col-form-label-sm' },
						$r->maketext('Section:')
					),
					CGI::div(
						{ class => 'col-10' },
						CGI::popup_menu({
							name    => 'library_sections',
							id      => 'library_sections',
							values  => \@sects,
							default => $r->param('library_sections') || LIB2_DATA->{dbsection}{all},
							class   => 'form-select form-select-sm'
						})
					)
				)
			),
			CGI::div(
				{ class =>
						'col-md-3 col-sm-4 mb-1 d-flex flex-sm-column justify-content-sm-start justify-content-center'
				},
				CGI::submit({
					name  => 'library_advanced',
					value => $r->maketext("Advanced Search"),
					class => 'btn btn-secondary btn-sm',
					style => 'max-width:9rem'
				})
			)
		),
		view_problems_line('lib_view', $r->maketext('View Problems'), $self->r),
		CGI::div(
			{ class => 'text-center', id => 'library_count_line' },
			CGI::label({ class => 'col-form-label-sm' }, $count_line)
		)
	);
}

sub browse_library_panel2adv {
	my $self = shift;
	my $r    = $self->r;

	my $right_button_style = 'max-width:9rem';

	my @subjs = WeBWorK::Utils::ListingDB::getAllDBsubjects($r);
	if (!grep { $_ eq $r->param('library_subjects') } @subjs) {
		$r->param('library_subjects', '');
	}
	unshift @subjs, LIB2_DATA->{dbsubject}{all};

	my @chaps = WeBWorK::Utils::ListingDB::getAllDBchapters($r);
	if (!grep { $_ eq $r->param('library_chapters') } @chaps) {
		$r->param('library_chapters', '');
	}
	unshift @chaps, LIB2_DATA->{dbchapter}{all};

	my @sects = WeBWorK::Utils::ListingDB::getAllDBsections($r);
	if (!grep { $_ eq $r->param('library_sections') } @sects) {
		$r->param('library_sections', '');
	}
	unshift @sects, LIB2_DATA->{dbsection}{all};

	my $texts      = WeBWorK::Utils::ListingDB::getDBTextbooks($r);
	my @textarray  = map { $_->[0] } @{$texts};
	my %textlabels = ();
	for my $ta (@{$texts}) {
		$textlabels{ $ta->[0] } = $ta->[1] . " by " . $ta->[2] . " (edition " . $ta->[3] . ")";
	}
	if (!grep { $_ eq $r->param('library_textbook') } @textarray) {
		$r->param('library_textbook', '');
	}
	unshift @textarray, LIB2_DATA->{textbook}{all};
	my $atb = LIB2_DATA->{textbook}{all};
	$textlabels{$atb} = LIB2_DATA->{textbook}{all};

	my $textchap_ref = WeBWorK::Utils::ListingDB::getDBTextbooks($r, 'textchapter');
	my @textchaps    = map { $_->[0] } @{$textchap_ref};
	if (!grep { $_ eq $r->param('library_textchapter') } @textchaps) {
		$r->param('library_textchapter', '');
	}
	unshift @textchaps, LIB2_DATA->{textchapter}{all};

	my $textsec_ref = WeBWorK::Utils::ListingDB::getDBTextbooks($r, 'textsection');
	my @textsecs    = map { $_->[0] } @{$textsec_ref};
	if (!grep { $_ eq $r->param('library_textsection') } @textsecs) {
		$r->param('library_textsection', '');
	}
	unshift @textsecs, LIB2_DATA->{textsection}{all};

	my %selected = ();
	for my $j (qw( dbsection dbchapter dbsubject textbook textchapter textsection )) {
		$selected{$j} = $r->param(LIB2_DATA->{$j}{name}) || LIB2_DATA->{$j}{all};
	}

	my $text_popup = CGI::popup_menu({
		name     => 'library_textbook',
		id       => 'library_textbook',
		values   => \@textarray,
		labels   => \%textlabels,
		default  => $selected{textbook},
		onchange => "submit();return true",
		class    => 'form-select form-select-sm'
	});

	my $count_line = WeBWorK::Utils::ListingDB::countDBListings($r);
	if ($count_line == 0) {
		$count_line = "There are no matching WeBWorK problems";
	} else {
		$count_line = "There are $count_line matching WeBWorK problems";
	}

	# Formatting level checkboxes by hand
	my %selected_levels = map { $_ => 1 } $r->param('level');

	my $mylevelline = CGI::div(
		{ class => 'd-flex justify-content-between align-items-center' },
		(
			map {
				CGI::div(
					{ class => 'form-check form-check-inline' },
					CGI::checkbox({
						name            => 'level',
						value           => $_,
						label           => $_,
						class           => 'form-check-input',
						checked         => defined($selected_levels{$_}),
						labelattributes => { class => 'form-check-label col-form-label-sm' }
					})
				)
			} 1 .. 6
		),
		$self->helpMacro("Levels")
	);

	print CGI::div(
		CGI::hidden({ name => "library_is_basic", default => 2, override => 1 }),
		CGI::div(
			{ class => 'text-center' },
			CGI::label({ class => 'col-form-label-sm pt-0' }, $r->maketext('All Selected Constraints Joined by "And"'))
		),
		CGI::div(
			{ class => 'row mb-1' },
			CGI::div({ class => 'col-md-3 mb-1' }, ''),
			CGI::div(
				{ class => 'col-md-6 col-sm-8 mb-1' },
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_subjects', class => 'col-3 col-form-label col-form-label-sm' },
						$r->maketext('Subject:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name    => 'library_subjects',
							id      => 'library_subjects',
							values  => \@subjs,
							default => $selected{dbsubject},
							class   => 'form-select form-select-sm',
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_chapters', class => 'col-3 col-form-label col-form-label-sm' },
						$r->maketext('Chapter:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name    => 'library_chapters',
							id      => 'library_chapters',
							values  => \@chaps,
							default => $selected{dbchapter},
							class   => 'form-select form-select-sm',
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_sections', class => 'col-3 col-form-label col-form-label-sm' },
						$r->maketext('Section:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name    => 'library_sections',
							id      => 'library_sections',
							values  => \@sects,
							default => $selected{dbsection},
							class   => 'form-select form-select-sm',
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_textbook', class => 'col-3 col-form-label col-form-label-sm' },
						$r->maketext('Textbook:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name     => 'library_textbook',
							id       => 'library_textbook',
							values   => \@textarray,
							labels   => \%textlabels,
							default  => $selected{textbook},
							onchange => "submit();return true",
							class    => 'form-select form-select-sm'
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_textchapter', class => 'col-3 col-form-label col-form-label-sm text-nowrap' },
						$r->maketext('Text chapter:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name     => 'library_textbook',
							id       => 'library_textbook',
							values   => \@textarray,
							labels   => \%textlabels,
							default  => $selected{textbook},
							onchange => "submit();return true",
							class    => 'form-select form-select-sm'
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_textsection', class => 'col-3 col-form-label col-form-label-sm text-nowrap' },
						$r->maketext('Text section:')
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::popup_menu({
							name     => 'library_textsection',
							id       => 'library_textsection',
							values   => \@textsecs,
							default  => $selected{textsection},
							onchange => "submit();return true",
							class    => 'form-select form-select-sm',
						})
					)
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label({ class => 'col-3 col-form-label col-form-label-sm' }, $r->maketext("Level:")),
					CGI::div({ class => 'col-9' }, $mylevelline),
				),
				CGI::div(
					{ class => 'row mb-1' },
					CGI::label(
						{ for => 'library_keywords', class => 'col-3 col-form-label col-form-label-sm' },
						$r->maketext("Keywords:")
					),
					CGI::div(
						{ class => 'col-9' },
						CGI::textfield({
							name     => "library_keywords",
							id       => "library_keywords",
							default  => $r->param('library_keywords') || '',
							override => 1,
							class    => 'form-control form-control-sm'
						})
					),
				)
			),
			CGI::div(
				{ class =>
						'col-md-3 col-sm-4 mb-1 d-flex flex-sm-column justify-content-sm-start justify-content-center'
				},
				CGI::submit({
					name  => "lib_select_subject",
					value => $r->maketext("Update Menus"),
					style => $right_button_style,
					class => 'btn btn-secondary btn-sm mb-1'
				}),
				CGI::submit({
					name  => "library_reset",
					value => $r->maketext("Reset"),
					style => $right_button_style,
					class => 'btn btn-secondary btn-sm mb-1 ms-sm-0 ms-2'
				}),
				CGI::submit({
					name  => "library_basic",
					value => $r->maketext("Basic Search"),
					style => $right_button_style,
					class => 'btn btn-secondary btn-sm mb-1 ms-sm-0 ms-2'
				})
			)
		),
		view_problems_line('lib_view', $r->maketext('View Problems'), $self->r),
		CGI::div(
			{ class => 'text-center', id => 'library_count_line' },
			CGI::label({ class => 'col-form-label-sm' }, $count_line)
		)
	);
}

# Version 4 is the set definition file panel
sub browse_setdef_panel {
	my $self             = shift;
	my $r                = $self->r;
	my $ce               = $r->ce;
	my $library_selected = shift;
	my $default_value    = 'Select a Set Definition File';

	# In the following line, the parens after sort are important. If they are
	# omitted, sort will interpret get_set_defs as the name of the comparison
	# function, and ($ce->{courseDirs}{templates}) as a single element list to
	# be sorted.
	my @list_of_set_defs = sort(get_set_defs($ce->{courseDirs}{templates}));

	if (scalar(@list_of_set_defs) == 0) {
		print CGI::div(
			{ class => 'InfoPanel' },
			CGI::label(
				{ class => 'col-form-label-sm' },
				$r->maketext('There are no set definition files in this course to look at.')
			)
		);
		return;
	}

	if (!defined $library_selected || $library_selected eq $default_value) {
		unshift @list_of_set_defs, $default_value;
		$library_selected = $default_value;
	}

	print CGI::div(
		{ class => 'InfoPanel' },
		CGI::div(
			{ class => 'mb-2' },
			CGI::label({ class => 'col-form-label-sm' }, $r->maketext('Browse from:')),
			CGI::popup_menu({
				name    => 'library_sets',
				values  => \@list_of_set_defs,
				default => $library_selected,
				class => 'form-select form-select-sm d-inline w-auto'
			})
		),
		view_problems_line('view_setdef_set', $r->maketext('View Problems'), $self->r)
	);
}

sub make_top_row {
	my $self = shift;
	my $r = $self->r;
	my $ce = $r->ce;
	my %data = @_;

	my $list_of_local_sets = $data{all_db_sets};
	my $have_local_sets = scalar(@$list_of_local_sets);
	my $browse_which = $data{browse_which};
	my $library_selected = $self->{current_library_set};
	my $set_selected = $r->param('local_sets');
	my (@dis1, @dis2, @dis3, @dis4) = ();
	@dis1 =	 (-disabled=>1) if($browse_which eq 'browse_npl_library');
	@dis2 =	 (-disabled=>1) if($browse_which eq 'browse_local');
	@dis3 =	 (-disabled=>1) if($browse_which eq 'browse_mysets');
	@dis4 =	 (-disabled=>1) if($browse_which eq 'browse_setdefs');

	my $these_widths = "width:9.3rem";

	if ($have_local_sets == 0) {
		$list_of_local_sets = [ $r->maketext(NO_LOCAL_SET_STRING) ];
	} elsif (!defined $set_selected || $set_selected eq $r->maketext(SELECT_SET_STRING)) {
		unshift @{$list_of_local_sets}, $r->maketext(SELECT_SET_STRING);
		$set_selected = $r->maketext(SELECT_SET_STRING);
	}
	my $courseID = $self->r->urlpath->arg("courseID");

	print CGI::hr({ class => 'mt-0 mb-2' });

	print CGI::div(
		{ class => 'd-flex flex-wrap justify-content-center' },
		CGI::div(
			{ class => 'd-flex flex-wrap justify-content-center mb-2' },
			CGI::label(
				{ for => 'local_sets', class => 'col-form-label-sm' },
				$r->maketext('Add problems to') . ' ' . CGI::b($r->maketext('Target Set:'))
			),
			CGI::popup_menu({
				name     => 'local_sets',
				id       => 'local_sets',
				values   => $list_of_local_sets,
				default  => $set_selected,
				override => 1,
				class    => 'form-select form-select-sm d-inline w-auto mx-2',
			})
		),
		CGI::submit({
			name  => "edit_local",
			value => $r->maketext("Edit Target Set"),
			class => 'btn btn-primary btn-sm mb-2'
		}),
		CGI::hidden({ name => 'selfassign', default => 0, override => 1 }),
	);

	print CGI::div(
		{ class => 'd-flex flex-wrap justify-content-center' },
		CGI::submit({
			name    => "new_local_set",
			value   => $r->maketext("Create a New Set in This Course:"),
			onclick => "document.library_browser_form.selfassign.value=1",
			class   => 'btn btn-primary btn-sm mb-2 mx-2'
		}),
		CGI::textfield({
			name     => "new_set_name",
			example  => $r->maketext("Name for new set here"),
			override => 1,
			size     => 30,
			class    => 'form-control form-control-sm d-inline w-auto mb-2'
		})
	);

	print CGI::hr({ class => 'mt-0 mb-2' });

	# Tidy this list up since it is used in two different places
	if ($list_of_local_sets->[0] eq $r->maketext(SELECT_SET_STRING)) {
		shift @{$list_of_local_sets};
	}

	print CGI::div(
		{ class => 'd-flex justify-content-center' },
		CGI::label({ class => 'col-form-label-sm mb-2 me-1' }, $r->maketext("Browse")),
		CGI::div(
			{ class => 'd-flex flex-wrap justify-content-center' },
			CGI::submit({
				name  => "browse_npl_library",
				value => $r->maketext("Open Problem Library"),
				style => $these_widths,
				class => 'btn btn-secondary btn-sm mb-2 mx-1',
				@dis1
			}),
			CGI::submit({
				name  => "browse_local",
				value => $r->maketext("Local Problems"),
				style => $these_widths,
				class => 'btn btn-secondary btn-sm mb-2 mx-1',
				@dis2
			}),
			CGI::submit({
				name  => "browse_mysets",
				value => $r->maketext("From This Course"),
				style => $these_widths,
				class => 'btn btn-secondary btn-sm mb-2 mx-1',
				@dis3
			}),
			CGI::submit({
				name  => "browse_setdefs",
				value => $r->maketext("Set Definition Files"),
				style => $these_widths,
				class => 'btn btn-secondary btn-sm mb-2 mx-1',
				@dis4
			})
		)
	);

	# Make buttons for additional problem libraries
	my $libs = '';
	foreach my $lib (sort(keys(%problib))) {
		$libs .= CGI::submit({
			name  => "browse_$lib",
			value => Encode::decode("UTF-8", $problib{$lib}),
			class => 'btn btn-secondary btn-sm ms-2 mb-2',
			($browse_which eq "browse_$lib") ? (disabled => undef) : ()
		})
			if (-d "$ce->{courseDirs}{templates}/$lib");
	}

	print CGI::div(
		{ class => 'd-flex justify-content-center' },
		CGI::label({ class => 'col-form-label-sm mb-2' }, $r->maketext("or Problems from")),
		CGI::div({ class => 'd-flex flex-wrap justify-content-center' }, $libs)
	) if $libs ne '';

	print CGI::hr({ class => 'mt-0 mb-2' });

	if ($browse_which eq 'browse_local') {
		$self->browse_local_panel($library_selected);
	} elsif ($browse_which eq 'browse_mysets') {
		$self->browse_mysets_panel($library_selected, $list_of_local_sets);
	} elsif ($browse_which eq 'browse_npl_library') {
		$self->browse_library_panel();
	} elsif ($browse_which eq 'browse_setdefs') {
		$self->browse_setdef_panel($library_selected);
	} else { ## handle other problem libraries
		$self->browse_local_panel($library_selected,$browse_which);
	}

	print CGI::hr({ class => 'mt-0 mb-2' });

    # For next/previous buttons
	my ($next_button, $prev_button) = ("", "");
	my $first_shown = $self->{first_shown};
	my $last_shown = $self->{last_shown};
	my $first_index = $self->{first_index};
	my $last_index = $self->{last_index};
	my @pg_files = @{$self->{pg_files}};
	if ($first_index > 0) {
		$prev_button = CGI::submit({
			name => "prev_page",
			style => $these_widths,
			value => $r->maketext("Previous page"),
			class => 'btn btn-secondary btn-sm mx-1 mb-2'
		});
	}
	# This will have to be trickier with MLT
	if ((1 + $last_index) < scalar(@pg_files)) {
		$next_button = CGI::submit({
			name => "next_page",
		   	style => $these_widths,
			value => $r->maketext("Next page"),
			class => 'btn btn-secondary btn-sm mx-1 mb-2'
		});
	}

	print CGI::div(
		{ class => 'd-flex flex-wrap justify-content-center' },
		CGI::button({
			name  => "select_all",
			style => $these_widths,
			value => $r->maketext("Add All"),
			class => 'btn btn-primary btn-sm mx-1 mb-2'
		}),
		CGI::submit({
			name  => "cleardisplay",
			style => $these_widths,
			value => $r->maketext("Clear Problem Display"),
			class => 'btn btn-secondary btn-sm mx-1 mb-2'
		}),
		$prev_button,
		$next_button
	);
}

sub make_data_row {
	my $self           = shift;
	my $r              = $self->r;
	my $ce             = $r->{ce};
	my $sourceFileData = shift;
	my $sourceFileName = $sourceFileData->{filepath};
	my $pg_file        = shift;
	my $isstatic       = $sourceFileData->{static};
	my $isMO           = $sourceFileData->{MO};

	if (not defined $isMO) {
		($isMO, $isstatic) = getDBextras($r, $sourceFileName);
	}
	my $cnt        = shift;
	my $mltnumleft = shift;

	$sourceFileName =~ s|^./||;    # clean up top ugliness

	my $urlpath = $self->r->urlpath;
	my $db      = $self->r->db;

	## to set up edit and try links elegantly we want to know if
	##    any target set is a gateway assignment or not
	my $localSet = $self->r->param('local_sets');
	my $setRecord;
	if (defined($localSet)
		&& $localSet ne $r->maketext(SELECT_SET_STRING)
		&& $localSet ne $r->maketext(NO_LOCAL_SET_STRING))
	{
		$setRecord = $db->getGlobalSet($localSet);
	}
	my $isGatewaySet = (defined($setRecord) && $setRecord->assignment_type =~ /gateway/);

	my $problem_seed = $self->{'problem_seed'} || 1234;
	my $edit_link = CGI::a(
		{
			href => $self->systemLink(
				$urlpath->newFromModule(
					"WeBWorK::ContentGenerator::Instructor::PGProblemEditor", $r,
					courseID  => $urlpath->arg("courseID"),
					setID     => "Undefined_Set",
					problemID => "1"
				),
				params => {
					sourceFilePath => $sourceFileName,
					problemSeed    => $problem_seed
				}
			),
			id                => "editit$cnt",
			target            => "WW_Editor",
			data_bs_title     => $r->maketext('Edit it'),
			class             => 'btn btn-sm btn-secondary',
			data_bs_toggle    => 'tooltip',
			data_bs_placement => 'top'
		},
		CGI::i({ class => 'icon fas fa-pencil-alt', data_alt => 'edit', aria_hidden => "true" }, "")
	);

	my $displayMode = $self->r->param("mydisplayMode");
	$displayMode = $self->r->ce->{pg}->{options}->{displayMode}
		if not defined $displayMode or $displayMode eq "None";
	my $module   = ($isGatewaySet) ? "GatewayQuiz" : "Problem";
	my %pathArgs = (
		courseID => $urlpath->arg("courseID"),
		setID    => "Undefined_Set"
	);
	$pathArgs{problemID} = "1" if (!$isGatewaySet);

	my $try_link = CGI::a(
		{
			href => $self->systemLink(
				$urlpath->newFromModule("WeBWorK::ContentGenerator::$module", $r, %pathArgs),
				params => {
					effectiveUser  => scalar($self->r->param('user')),
					editMode       => "SetMaker",
					problemSeed    => $problem_seed,
					sourceFilePath => "$sourceFileName",
					displayMode    => $displayMode,
				}
			),
			target            => "WW_View",
			data_bs_title     => $r->maketext('Try it'),
			id                => "tryit$cnt",
			class             => 'text-decoration-none btn btn-sm btn-secondary',
			data_bs_toggle    => 'tooltip',
			data_bs_placement => 'top'
		},
		CGI::i({ class => 'far fa-eye' }, '')
	);

	my $mlt = '';
	my ($mltstart, $mltend) = ('', '');
	my $noshowclass = $sourceFileData->{morelt} ? "MLT$sourceFileData->{morelt}" : "NS$cnt";
	if ($sourceFileData->{children}) {
		my $numchild = scalar(@{ $sourceFileData->{children} });
		$mlt = CGI::span(
			{
				class                 => 'lb-mlt-parent btn btn-sm btn-secondary',
				id                    => "mlt$cnt",
				data_mlt_cnt          => $cnt,
				data_mlt_noshow_class => $noshowclass,
				data_less_text        => $r->maketext('Show less like this'),
				data_more_text        => $r->maketext('Show [_1] more like this', $numchild),
				data_bs_title         => $r->maketext('Show [_1] more like this', $numchild),
				data_bs_toggle        => 'tooltip',
				data_bs_placement     => 'top',
				tabindex              => 0,
				role                  => 'button'
			},
			'M'
		);
		$noshowclass = "NS$cnt";
		$mltstart    = CGI::start_div({ id => "mlt-table$cnt", class => 'lb-mlt-group' });
	}
	$mltend = CGI::end_div() if ($mltnumleft == 0);
	my $noshow = $sourceFileData->{noshow} ? 'display:none' : '';

	# Include tagwidget?
	my $tagwidget = '';
	my $user      = scalar($r->param('user'));
	if ($r->authz->hasPermissions($user, "modify_tags")) {
		my $tagid = 'tagger' . $cnt;
		$tagwidget = CGI::div({ id => $tagid }, '');
		my $templatedir    = $r->ce->{courseDirs}->{templates};
		my $sourceFilePath = $templatedir . '/' . $sourceFileName;
		$sourceFilePath =~ s/'/\\'/g;
		my $site_url = $r->ce->{webworkURLs}->{htdocs};
		$tagwidget .= CGI::script("mytw$cnt = new tag_widget('$tagid','$sourceFilePath')");
	}

	my $level = 0;

	my $rerand = $isstatic ? '' : CGI::span(
		{
			data_target_problem => $cnt,
			class               => 'rerandomize_problem_button btn btn-sm btn-secondary',
			data_bs_title       => $r->maketext('Randomize'),
			data_bs_toggle      => 'tooltip',
			data_bs_placement   => 'top',
			tabindex            => 0,
			role                => 'button',
			aria_label          => 'rerandomize problem'
		},
		CGI::i({ class => 'fas fa-random', aria_hidden => 'true' }, '')
	);
	my $MOtag = CGI::span(
		{ class => 'motag' },
		$isMO
		? CGI::span(
			{
				class           => 'info-button btn btn-sm btn-secondary',
				title           => $r->maketext('Uses Math Objects'),
				data_bs_content => $r->maketext(
					'Some WeBWorK problems are programmed using what are called <i>Math Objects</i>. '
						. 'These problems are preferred by some people because they '
						. 'provide a more consistent collection of messages to faulty student '
						. 'answers, particularly for answers which are way off base.'
				),
				data_bs_toggle    => 'popover',
				data_bs_placement => 'top',
				data_bs_html      => 'true',
				data_bs_trigger   => 'hover focus',
				tabindex          => 0,
				role              => 'button'
			},
			CGI::img({
				src => $r->ce->{webworkURLs}{htdocs} . '/images/pi.svg',
				alt => $r->maketext('Uses Math Objects')
			})
		)
		: ''
	);

	# Get statistics to display

	my $global_problem_stats = '';
	if ($ce->{problemLibrary}{showLibraryGlobalStats}) {
		my $stats = $self->{library_stats_handler}->getGlobalStats($sourceFileName);
		if ($stats->{students_attempted}) {
			$global_problem_stats = CGI::div(
				{ class => 'd-inline-block font-sm text-nowrap' },
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Global Usage Data'),
						data_bs_content => $r->maketext(
							'Global data on problem usage is contributed by many institutions using '
								. 'WeBWorK all over the world. The Usage figure is the total number of  '
								. 'individuals who have attemped this problem at least once. A high figure '
								. 'represents a problem which has been assigned to many students and is  '
								. 'both popular with instructors and likely bug free.'
						),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_trigger   => 'hover focus',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('GLOBAL Usage') . ': '
				),
				$stats->{students_attempted} . ', ',
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Global Attempts'),
						data_bs_content => $r->maketext(
							'The Attempts figure is the global average of the number of attempts '
								. '(both correct and incorrect) individuals take on this problem.  '
								. 'A high figure may represent a difficult problem.  Note that problems '
								. 'with multiple parts may have higher average attempts since many students  '
								. 'will submit an answer to each part before continuing and each such  '
								. 'submittal counts as an attempt.'
						),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_trigger   => 'hover focus',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('Attempts') . ': '
				),
				wwRound(2, $stats->{average_attempts}) . ', ',
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Global Status'),
						data_bs_content => CGI::p($r->maketext(
							'The Status figure is the global average of the Status '
								. 'individuals have earned on this problem. The Status is the percentage '
								. 'correct (from 0% to 100%) recorded for the problem.  A low figure may  '
								. 'represent a difficult problem.  The Status is often fairly high since  '
								. 'many students will work on a problem until they get it correct or nearly so.'
						))
							. CGI::p({ class => 'mb-0' }, $r->maketext(
							'Reviewing a problem and looking at both the average Attempts and  '
								. 'average Status should give instructors valuable information about '
								. 'the difficulty of the problem.'
							)),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_html      => 'true',
						data_bs_trigger   => 'hover focus',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('Status') . ': '
				),
				wwRound(0, 100 * $stats->{average_status})
			);
		}
	}

	my $local_problem_stats = '';
	if ($ce->{problemLibrary}{showLibraryLocalStats}) {
		my $stats = $self->{library_stats_handler}->getLocalStats($sourceFileName);
		if ($stats->{students_attempted}) {
			$local_problem_stats = CGI::div(
				{ class => 'd-inline-block font-sm text-nowrap' },
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Local Usage Data'),
						data_bs_content => CGI::p($r->maketext(
							'Local data on problem usage is generated and maintained by your institution. '
								. 'The Usage figure is the total number of local '
								. 'individuals who have attemped this problem at least once. A high figure '
								. 'represents a problem which has been assigned to many students and is  '
								. 'both popular with instructors and likely bug free.'
						))
							. CGI::p({ class => 'mb-0' }, $r->maketext(
							'Local data is generated when your systems admin runs the script '
								. 'update-OPL-statistics.'
							)),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_trigger   => 'hover focus',
						data_bs_html      => 'true',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('LOCAL Usage') . ': '
				),
				$stats->{students_attempted} . ', ',
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Local Attempts'),
						data_bs_content => $r->maketext(
							'The Attempts figure is the local average of the number of attempts '
								. '(both correct and incorrect) individuals at your institution take on this problem. '
								. 'A high figure may represent a difficult problem.  Note that problems '
								. 'with multiple parts may have higher average attempts since many students  '
								. 'will submit an answer to each part before continuing and each such  '
								. 'submittal counts as an attempt.'
						),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_trigger   => 'hover focus',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('Attempts') . ': '
				),
				wwRound(2, $stats->{average_attempts}) . ', ',
				CGI::span(
					{
						class           => 'info-button text-primary',
						title           => $r->maketext('Local Status'),
						data_bs_content => CGI::p($r->maketext(
							'The Status figure is the local average of the Status '
								. 'individuals at your institution have earned on this problem. The Status is the '
								. 'percentage correct (from 0% to 100%) recorded for the problem.  A low figure may  '
								. 'represent a difficult problem.  The Status is often fairly high since  '
								. 'many students will work on a problem until they get it correct or nearly so.'
						))
							. CGI::p({ class => 'mb-0' }, $r->maketext(
							'Reviewing a problem and looking at both the average Attempts and  '
								. 'average Status should give instructors valuable information about '
								. 'the difficulty of the problem.'
							)),
						data_bs_toggle    => 'popover',
						data_bs_placement => 'top',
						data_bs_html      => 'true',
						data_bs_trigger   => 'hover focus',
						tabindex          => 0,
						role              => 'button'
					},
					$r->maketext('Status') . ': '
				),
				wwRound(0, 100 * $stats->{average_status})
			);
		}
	}

	my $problem_stats = '';
	if ($global_problem_stats || $local_problem_stats) {
		$problem_stats = $global_problem_stats . $local_problem_stats;
	}

	print $mltstart;
	# Print the cell
	print CGI::div(
		{ id => "pgrow$cnt", style => $noshow, class => "lb-problem-row $noshowclass" },
		CGI::div(
			{ class => 'card p-2' },
			CGI::div(
				{ class => 'lb-problem-header d-flex flex-wrap justify-content-between' },
				CGI::div(
					{ class => 'lb-problem-add d-flex align-items-center mb-1' },
					CGI::button({
						name              => 'add_me',
						value             => $r->maketext('Add'),
						data_bs_title     => $r->maketext('Add problem to target set'),
						data_source_file  => $sourceFileName,
						class             => 'btn btn-primary btn-sm',
						data_bs_toggle    => 'tooltip',
						data_bs_placement => 'top'
					}),
				),
				CGI::div({ class => 'd-flex flex-wrap align-items-center mb-1 gap-2' },
					$problem_stats),
				CGI::div(
					{ class => 'lb-problem-icons mb-1 d-flex align-items-center' },
					$MOtag, $mlt, $rerand,
					$edit_link,
					$try_link,
					CGI::span(
						{
							class             => 'dont-show btn btn-sm btn-secondary',
							data_bs_title     => $r->maketext('Hide this problem'),
							data_row_cnt      => $cnt,
							data_bs_toggle    => 'tooltip',
							data_bs_placement => 'top',
							tabindex          => 0,
							role              => 'button',
							aria_label        => 'hide this problem'
						},
						CGI::i({ class => 'fas fa-times', aria_hidden => 'true' }, '')
					)
				)
			),
			CGI::div(
				{ class => 'lb-problem-sub-header d-flex' },
				CGI::div({ class => 'lb-problem-path font-sm flex-grow-1 flex-shrink-1' }, $sourceFileName),
				CGI::div(
					{ class => 'lb-inset text-nowrap', id => "inset$cnt" },
					$self->{isInSet}{$sourceFileName} ? CGI::i(CGI::b('(in target set)')) : ''
				)
			),
			CGI::hidden({ name => "filetrial$cnt", default => $sourceFileName, override => 1 }),
			$tagwidget,
			CGI::div(
				CGI::div({ class => 'psr_render_area', id => "psr_render_area_$cnt", data_pg_file => $pg_file }, ''),
				''
			)
		)
	);
	print $mltend;
}

sub clear_default {
	my $r = shift;
	my $param = shift;
	my $default = shift;
	my $newvalue = $r->param($param) || '';
	$newvalue = '' if($newvalue eq $default);
	$r->param($param, $newvalue);
}

### Mainly deal with more like this

sub process_search {
	my $r = shift;
	my @dbsearch = @_;
	# Build a hash of MLT entries keyed by morelt_id
	my %mlt = ();
	my $mltind;
	for my $indx (0..$#dbsearch) {
		$dbsearch[$indx]->{filepath} = "Library/".$dbsearch[$indx]->{path}."/".$dbsearch[$indx]->{filename};
# For debugging
$dbsearch[$indx]->{oindex} = $indx;
		if($mltind = $dbsearch[$indx]->{morelt}) {
			if(defined($mlt{$mltind})) {
				push @{$mlt{$mltind}}, $indx;
			} else {
				$mlt{$mltind} = [$indx];
			}
		}
	}
	# Now filepath is set and we have a hash of mlt entries

	# Find MLT leaders, mark entries for no show,
	# set up children array for leaders
	for my $mltid (keys %mlt) {
		my @idlist = @{$mlt{$mltid}};
		if(scalar(@idlist)>1) {
			my $leader = WeBWorK::Utils::ListingDB::getMLTleader($r, $mltid) || 0;
			my $hold = undef;
			for my $subindx (@idlist) {
				if($dbsearch[$subindx]->{pgid} == $leader) {
					$dbsearch[$subindx]->{children}=[];
					$hold = $subindx;
				} else {
					$dbsearch[$subindx]->{noshow}=1;
				}
			}
			do { # we did not find the leader
				$hold = $idlist[0];
				$dbsearch[$hold]->{noshow} = undef;
				$dbsearch[$hold]->{children}=[];
			} unless($hold);
			$mlt{$mltid} = $dbsearch[$hold]; # store ref to leader
		} else { # only one, no more
			$dbsearch[$idlist[0]]->{morelt} = 0;
			delete $mlt{$mltid};
		}
	}

	# Put children in leader and delete them, record index of leaders
	$mltind = 0;
	while ($mltind < scalar(@dbsearch)) {
		if($dbsearch[$mltind]->{noshow}) {
			# move the entry to the leader
			my $mltval = $dbsearch[$mltind]->{morelt};
			push @{$mlt{$mltval}->{children}}, $dbsearch[$mltind];
			splice @dbsearch, $mltind, 1;
		} else {
			if($dbsearch[$mltind]->{morelt}) { # a leader
				for my $mltid (keys %mlt) {
					if($mltid == $dbsearch[$mltind]->{morelt}) {
						$mlt{$mltid}->{index} = $mltind;
						last;
					}
				}
			}
			$mltind++;
		}
	}
	# Last pass, reinsert children into dbsearch
	my @leaders = keys(%mlt);
	@leaders = reverse sort {$mlt{$a}->{index} <=> $mlt{$b}->{index}} @leaders;
	for my $i (@leaders) {
		my $base = $mlt{$i}->{index};
		splice @dbsearch, $base+1, 0, @{$mlt{$i}->{children}};
	}

	return @dbsearch;
}

sub pre_header_initialize {
	my ($self) = @_;
	my $r = $self->r;
	## For all cases, lets set some things
	$self->{error}=0;
	my $ce = $r->ce;
	my $db = $r->db;
	my $maxShown = $r->param('max_shown') || MAX_SHOW_DEFAULT;
	$maxShown = 10000000 if($maxShown eq 'All'); # let's hope there aren't more
	my $library_basic = $r->param('library_is_basic') || 1;
	$self->{problem_seed} = $r->param('problem_seed') || 1234;
	## Fix some parameters
	for my $key (keys(%{ LIB2_DATA() })) {
		clear_default($r, LIB2_DATA->{$key}->{name}, LIB2_DATA->{$key}->{all} );
	}
	##  Grab library sets to display from parameters list.  We will
	##  modify this as we go through the if/else tree
	$self->{current_library_set} =  $r->param('library_sets');

	##	These directories will have individual buttons
	%problib = %{$ce->{courseFiles}{problibs}} if $ce->{courseFiles}{problibs};

	my $userName = $r->param('user');
	my $user = $db->getUser($userName); # checked
	die "record for user $userName (real user) does not exist."
		unless defined $user;
	my $authz = $r->authz;
	unless ($authz->hasPermissions($userName, "modify_problem_sets")) {
		return(""); # Error message already produced in the body
	}

	## Now one action we have to deal with here
	if ($r->param('edit_local')) {
		my $urlpath = $r->urlpath;
		my $db = $r->db;
		my $checkset = $db->getGlobalSet($r->param('local_sets'));
		if (not defined($checkset)) {
			$self->{error} = 1;
			$self->addbadmessage($r->maketext('You need to select a "Target Set" before you can edit it.'));
		} else {
			my $page = $urlpath->newFromModule('WeBWorK::ContentGenerator::Instructor::ProblemSetDetail',  $r, setID=>$r->param('local_sets'), courseID=>$urlpath->arg("courseID"));
			my $url = $self->systemLink($page);
			$self->reply_with_redirect($url);
		}
	}

	## Next, lots of set up so that errors can be reported with message()

	############# List of problems we have already printed

	$self->{past_problems} = get_past_problem_files($r);
	# if we don't end up reusing problems, this will be wiped out
	# if we do redisplay the same problems, we must adjust this accordingly
	my $none_shown = scalar(@{$self->{past_problems}})==0;
	my @pg_files=();
	my $use_previous_problems = 1;
	my $first_shown = $r->param('first_shown') || 0;
	my $last_shown = $r->param('last_shown');
	if (not defined($last_shown)) {
		$last_shown = -1;
	}
	my $first_index = $r->param('first_index') || 0;
	my $last_index = $r->param('last_index');
	if (not defined($last_index)) {
		$last_index = -1;
	}
	my $total_probs = $r->param('total_probs') || 0;
	my @all_past_list = (); # these are include requested, but not shown
	my ($j, $count, $omlt, $nmlt, $hold) = (0,0,-1,0,0);
	while (defined($r->param("all_past_list$j"))) {
		$nmlt = $r->param("all_past_mlt$j") || 0;
		push @all_past_list, {'filepath' => $r->param("all_past_list$j"), 'morelt' => $nmlt};
		if($nmlt != $omlt or $nmlt == 0) {
			$count++ if($j>0);
			if($j>$hold+1) {
				$all_past_list[$hold]->{children} = [2..($j-$hold)];
			}
			$omlt = $nmlt;
			$hold = $j;
		} else { # equal and nonzero, so a child
			$all_past_list[$j]->{noshow} = 1;
		}
		$j++;
	}
	if($nmlt && $j-$hold>1) { $all_past_list[$hold]->{children} = [ 2..($j-$hold)]; }
	$count++ if($j>0);

	############# Default of which problem selector to display

	my $browse_which = $r->param('browse_which') || 'browse_npl_library';

	## check for problem lib buttons
	my $browse_lib = '';
	foreach my $lib (keys %problib) {
		if ($r->param("browse_$lib")) {
			$browse_lib = "browse_$lib";
			last;
		}
	}

	########### Start the logic through if elsif elsif ...
    debug("browse_lib", $r->param("$browse_lib"));
    debug("browse_npl_library", $r->param("browse_npl_library"));
    debug("browse_mysets", $r->param("browse_mysets"));
    debug("browse_setdefs", $r->param("browse_setdefs"));
	##### Asked to browse certain problems
	if ($browse_lib ne '') {
		$browse_which = $browse_lib;
		$self->{current_library_set} = "";
		$use_previous_problems = 0; @pg_files = (); ## clear old problems
	} elsif ($r->param('browse_npl_library')) {
		$browse_which = 'browse_npl_library';
		$self->{current_library_set} = "";
		$use_previous_problems = 0; @pg_files = (); ## clear old problems
	} elsif ($r->param('browse_local')) {
		$browse_which = 'browse_local';
		$use_previous_problems = 0; @pg_files = (); ## clear old problems
	} elsif ($r->param('browse_mysets')) {
		$browse_which = 'browse_mysets';
		$use_previous_problems = 0; @pg_files = (); ## clear old problems
	} elsif ($r->param('browse_setdefs')) {
		$browse_which = 'browse_setdefs';
		$self->{current_library_set} = "";
		$use_previous_problems = 0; @pg_files = (); ## clear old problems

		##### Change the seed value

	} elsif ($r->param('rerandomize')) {
		$self->{problem_seed}= 1+$self->{problem_seed};
		#$r->param('problem_seed', $problem_seed);
		$self->addbadmessage($r->maketext('Changing the problem seed for display, but there are no problems showing.')) if $none_shown;

		##### Clear the display

	} elsif ($r->param('cleardisplay')) {
		@pg_files = ();
		$use_previous_problems=0;
		$self->addbadmessage($r->maketext('The display was already cleared.')) if $none_shown;

		##### View problems selected from the local list

	} elsif ($r->param('view_local_set')) {

		my $set_to_display = $self->{current_library_set};
		if (not defined($set_to_display) or $set_to_display eq $r->maketext(SELECT_LOCAL_STRING) or $set_to_display eq "Found no directories containing problems") {
			$self->addbadmessage($r->maketext('You need to select a set to view.'));
		} else {
			$set_to_display = '.' if $set_to_display eq $r->maketext(MY_PROBLEMS);
			$set_to_display = substr($browse_which,7) if $set_to_display eq $r->maketext(MAIN_PROBLEMS);
			@pg_files = list_pg_files($ce->{courseDirs}->{templates},
				"$set_to_display");
			@pg_files = map {{'filepath'=> $_, 'morelt'=>0}} @pg_files;
			$use_previous_problems=0;
		}

		##### View problems selected from the a set in this course

	} elsif ($r->param('view_mysets_set')) {

		my $set_to_display = $self->{current_library_set};
		debug("set_to_display is $set_to_display");
		if (not defined($set_to_display)
				or $set_to_display eq "Select a Homework Set"
				or $set_to_display eq $r->maketext(NO_LOCAL_SET_STRING)) {
			$self->addbadmessage($r->maketext("You need to select a set from this course to view."));
		} else {
			@pg_files = map { { 'filepath' => $_->source_file, 'morelt' => 0 } }
				$db->getGlobalProblemsWhere({ set_id => $set_to_display });
			$use_previous_problems = 0;
		}

		##### View from the library database

	} elsif ($r->param('lib_view')) {

		@pg_files=();
		my @dbsearch = WeBWorK::Utils::ListingDB::getSectionListings($r);
		@pg_files = process_search($r, @dbsearch);
		$use_previous_problems=0;

		##### View a set from a set*.def

	} elsif ($r->param('view_setdef_set')) {

		my $set_to_display = $self->{current_library_set};
		debug("set_to_display is $set_to_display");
		if (not defined($set_to_display)
				or $set_to_display eq "Select a Set Definition File"
				or $set_to_display eq $r->maketext(NO_LOCAL_SET_STRING)) {
			$self->addbadmessage($r->maketext("You need to select a set definition file to view."));
		} else {
			@pg_files= $self->read_set_def($set_to_display);
			@pg_files = map {{'filepath'=> $_, 'morelt'=>0}} @pg_files;
		}
		$use_previous_problems=0;

		##### Edit the current local homework set

	} elsif ($r->param('edit_local')) { ## Jump to set edit page

		; # already handled


		##### Make a new local homework set

	} elsif ($r->param('new_local_set')) {
		if ($r->param('new_set_name') !~ /^[\w .-]*$/) {
			$self->addbadmessage($r->maketext("The name '[_1]' is not a valid set name.  Use only letters, digits, -, _, and .",$r->param('new_set_name')));
		} else {
			my $newSetName = $r->param('new_set_name');
			# if we want to munge the input set name, do it here
			$newSetName =~ s/\s/_/g;
			debug("local_sets was ", $r->param('local_sets'));
			$r->param('local_sets',$newSetName);  ## use of two parameter param
			debug("new value of local_sets is ", $r->param('local_sets'));
			my $newSetRecord	 = $db->getGlobalSet($newSetName);
			if (! $newSetName) {
			    $self->addbadmessage($r->maketext("You did not specify a new set name."));
			} elsif (defined($newSetRecord)) {
			    $self->addbadmessage($r->maketext("The set name '[_1]' is already in use.  Pick a different name if you would like to start a new set.",$newSetName));
			} else {			# Do it!
				$newSetRecord = $db->newGlobalSet();
				$newSetRecord->set_id($newSetName);
				$newSetRecord->set_header("defaultHeader");
				$newSetRecord->hardcopy_header("defaultHeader");
				# It's convenient to set the due date two weeks from now so that it is
				# not accidentally available to students.

				my $dueDate = time+2*60*60*24*7;
				my $display_tz = $ce->{siteDefaults}{timezone};
				my $fDueDate = $self->formatDateTime($dueDate, $display_tz, "%m/%d/%Y at %I:%M%P");
				my $dueTime = $ce->{pg}{timeAssignDue};

				# We replace the due time by the one from the config variable
				# and try to bring it back to unix time if possible
				$fDueDate =~ s/\d\d:\d\d(am|pm|AM|PM)/$dueTime/;

				$dueDate = $self->parseDateTime($fDueDate, $display_tz);
				$newSetRecord->open_date($dueDate - 60*$ce->{pg}{assignOpenPriorToDue});
				$newSetRecord->due_date($dueDate);
				$newSetRecord->answer_date($dueDate + 60*$ce->{pg}{answersOpenAfterDueDate});

				$newSetRecord->visible(1);
				$newSetRecord->enable_reduced_scoring(0);
				$newSetRecord->assignment_type('default');
				eval {$db->addGlobalSet($newSetRecord)};
				if ($@) {
					$self->addbadmessage("Problem creating set $newSetName<br> $@");
				} else {
					$self->addgoodmessage($r->maketext("Set [_1] has been created.", $newSetName));
					my $selfassign = $r->param('selfassign') || "";
					$selfassign = "" if($selfassign =~ /false/i); # deal with javascript false
					if($selfassign) {
						$self->assignSetToUser($userName, $newSetRecord);
						$self->addgoodmessage($r->maketext("Set [_1] was assigned to [_2]", $newSetName,$userName));
					}
				}
			}
		}

	} elsif ($r->param('next_page')) {
		# Can set first/last problem, but not index yet
		$first_index = $last_index+1;
		my $oli = 0;
		my $cnt = 0;
		while(($oli = next_prob_group($last_index, @all_past_list)) != -1 and $cnt<$maxShown) {
			$cnt++;
			$last_index = $oli;
		}
		$last_index = end_prob_group($last_index, @all_past_list);
	} elsif ($r->param('prev_page')) {
		# Can set first/last index, but not problem yet
		$last_index = $first_index-1;
		my $oli = 0;
		my $cnt = 0;
		while(($oli = prev_prob_group($first_index, @all_past_list)) != -1 and $cnt<$maxShown) {
			$cnt++;
			$first_index = $oli;
		}
		$first_index = 0 if($first_index<0);

	#} elsif ($r->param('select_all')) {
		#;
	} elsif ($r->param('library_basic')) {
		$library_basic = 1;
		for my $jj (qw(textchapter textsection textbook)) {
			$r->param('library_'.$jj,'');
		}
	} elsif ($r->param('library_advanced')) {
		$library_basic = 2;
	} elsif ($r->param('library_reset')) {
		for my $jj (qw(chapters sections subjects textbook keywords)) {
			$r->param('library_'.$jj,'');
		}
	#} elsif ($r->param('select_none')) {
	#	;
	} else {
		##### No action requested, probably our first time here
		;
	}				##### end of the if elsif ...


	# Get the list of local sets sorted by set_id.
	my @all_db_sets = map { $_->[0] } $db->listGlobalSetsWhere({}, 'set_id');

	if ($use_previous_problems) {
		@pg_files = @all_past_list;
		$first_shown = 0;
		$last_shown = 0;
		my ($oli, $cnt) = (0,0);
		while($oli < $first_index and ($oli = next_prob_group($first_shown, @pg_files)) != -1) {
			$cnt++;
			$first_shown = $oli;
		}
		$first_shown = $cnt;
		$last_shown = $oli;
		while($oli <= $last_index and $oli != -1) {
			$oli = next_prob_group($last_shown, @pg_files);
			$cnt++;
			$last_shown = $oli;
		}
		$last_shown = $cnt-1;
		$total_probs = $count;
	} else {
		### Main place to set first/last shown for new problems
		$first_shown = 0;
		$first_index = 0;
		$last_index = 0;
		$last_shown = 1;
		$total_probs = 0;
		my $oli = 0;
		while(($oli = next_prob_group($last_index, @pg_files)) != -1 and $last_shown<$maxShown) {
			$last_shown++;
			$last_index = $oli;
		}
		$total_probs = $last_shown;
		# $last_index points to start of last group
		$last_shown--; # first_shown = 0
		$last_index = end_prob_group($last_index, @pg_files);
		$oli = $last_index;
		while(($oli = next_prob_group($oli, @pg_files)) != -1) {
			$total_probs++;
		}
	}


        my $library_stats_handler = '';

	if ($ce->{problemLibrary}{showLibraryGlobalStats} ||
	   $ce->{problemLibrary}{showLibraryLocalStats} ) {
	    $library_stats_handler = WeBWorK::Utils::LibraryStats->new($ce);
	}

	############# Now store data in self for retreival by body
	$self->{first_shown} = $first_shown;
	$self->{last_shown} = $last_shown;
	$self->{first_index} = $first_index;
	$self->{last_index} = $last_index;
	$self->{total_probs} = $total_probs;
	$self->{browse_which} = $browse_which;
	#$self->{problem_seed} = $problem_seed;
	$self->{pg_files} = \@pg_files;
	$self->{all_db_sets} = \@all_db_sets;
	$self->{library_basic} = $library_basic;
	$self->{library_stats_handler} = $library_stats_handler;
}


sub title {
	my ($self) = @_;
	return $self->r->maketext("Library Browser");
}

sub body {
	my ($self) = @_;

	my $r = $self->r;
	my $ce = $r->ce;		# course environment
	my $db = $r->db;		# database
	my $j;			# garden variety counter

	my $courseID = $self->r->urlpath->arg("courseID");
	my $userName = $r->param('user');

	my $user = $db->getUser($userName); # checked
	die "record for user $userName (real user) does not exist."
		unless defined $user;

	### Check that this is a professor
	my $authz = $r->authz;
	unless ($authz->hasPermissions($userName, "modify_problem_sets")) {
		print "User $userName returned " . $authz->hasPermissions($userName, "modify_problem_sets") . " for permission";
		return (CGI::div(
			{ class => 'alert alert-danger p-1 mb-0' },
			CGI::em("You are not authorized to access the Instructor tools.")
		));
	}

	my $showHints = $r->param('showHints');
	my $showSolutions = $r->param('showSolutions');

	##########	Extract information computed in pre_header_initialize

	my $first_shown = $self->{first_shown};
	my $last_shown = $self->{last_shown};
	my $first_index = $self->{first_index};
	my $last_index = $self->{last_index};
	my $total_probs = $self->{total_probs};
	my $browse_which = $self->{browse_which};
	my $problem_seed = $self->{problem_seed}||1234;
	my @pg_files = @{$self->{pg_files}};
	my @all_db_sets = @{$self->{all_db_sets}};

	my @plist = map {$_->{filepath}} @pg_files[$first_index..$last_index];

	# If there are problems to view and a target set is selected, then create a hash of source files in the target set.
	if (@plist) {
		my $setName = $r->param("local_sets");
		if (defined $setName) {
			$self->{isInSet} =
				{ map { $_->[0] => 1 } $db->{problem}->get_fields_where(['source_file'], { set_id => $setName }) };
		}
	}

	##########	Top part
	my $webwork_htdocs_url = $ce->{webwork_htdocs_url};
	print CGI::start_form({ method => "POST", action => $r->uri, name => 'library_browser_form' }),
		$self->hidden_authen_fields,
		CGI::hidden({ id => 'hidden_courseID', name => 'courseID', default => $courseID });
	print CGI::hidden(-name=>'browse_which', -value=>$browse_which,-override=>1),
		CGI::hidden(-name=>'problem_seed', -value=>$problem_seed, -override=>1);
	for ($j = 0 ; $j < scalar(@pg_files) ; $j++) {
		print CGI::hidden(-name=>"all_past_list$j", -value=>$pg_files[$j]->{filepath}, -override=>1)."\n";
		print CGI::hidden(-name=>"all_past_mlt$j", -value=>($pg_files[$j]->{morelt} || 0), -override=>1)."\n";
	}

	print CGI::hidden(-name=>'first_shown', -value=>$first_shown,-override=>1);

	print CGI::hidden(-name=>'last_shown', -value=>$last_shown, -override=>1);
	print CGI::hidden(-name=>'first_index', -value=>$first_index);
	print CGI::hidden(-name=>'last_index', -value=>$last_index);
	print CGI::hidden(-name=>'total_probs', -value=>$total_probs);

	print CGI::start_div({ class => 'library-browser-table' });
	$self->make_top_row('all_db_sets' => \@all_db_sets, 'browse_which' => $browse_which);
	print CGI::end_div();

	########## Now print problems
	my ($jj,$mltnumleft)=(0,-1);
	for ($jj=0; $jj<scalar(@plist); $jj++) {
		$pg_files[$jj+$first_index]->{filepath} =~ s|^$ce->{courseDirs}->{templates}/?||;
		# For MLT boxes, need to know if we are at the end of a group
		# make_data_row can't figure this out since it only sees one file
		$mltnumleft--;
		my $sourceFileData = $pg_files[$jj+$first_index];
		$self->make_data_row($sourceFileData, $plist[$jj], $jj+1,$mltnumleft);
		$mltnumleft = scalar(@{$sourceFileData->{children}}) if($sourceFileData->{children});
	}

	########## Finish things off
	my ($next_button, $prev_button) = ("", "");
	if ($first_index > 0) {
		$prev_button = CGI::submit({
			name => "prev_page",
			value => $r->maketext("Previous page"),
			class => 'btn btn-secondary btn-sm'
		});
	}
	if ((1+$last_index)<scalar(@pg_files)) {
		$next_button = CGI::submit({
			name => "next_page",
			value => $r->maketext("Next page"),
			class => 'btn btn-secondary btn-sm'
		});
	}
	if (scalar(@pg_files) > 0) {
		print CGI::div(
			{ class => 'my-2' },
			CGI::span(
				{ id => 'what_shown' },
				CGI::span({ id => 'firstshown' }, $first_shown + 1) . "-"
					. CGI::span({ id => 'lastshown' }, $last_shown + 1)
				)
				. " "
				. $r->maketext("of") . " "
				. CGI::span({ id => 'totalshown' }, $total_probs) . " "
				. $r->maketext("shown") . ".",
			$prev_button,
			" ",
			$next_button,
		);
		print CGI::p(
			$r->maketext(
				'Some problems shown above represent multiple similar problems from the database.  If the (top) '
					. 'information line for a problem has a letter M for "More", hover your mouse over the M  to '
					. 'see how many similar problems are hidden, or click on the M to see the problems.  If you click '
					. 'to view these problems, the M becomes an L, which can be clicked on to hide the problems again.'
				)
		);
	}

	print CGI::end_form();

	return "";
}

sub output_JS {
	my ($self)             = @_;
	my $ce                 = $self->r->ce;
	my $webwork_htdocs_url = $ce->{webwork_htdocs_url};

	print CGI::script({ src => "$webwork_htdocs_url/js/apps/Base64/Base64.js" },                            '');
	print CGI::script({ src => "$webwork_htdocs_url/js/apps/Knowls/knowl.js", defer => undef },             '');
	print CGI::script({ src => "$webwork_htdocs_url/js/apps/ImageView/imageview.js", defer => undef },      '');
	print CGI::script({ src => "$webwork_htdocs_url/node_modules/iframe-resizer/js/iframeResizer.min.js" }, '');
	print CGI::script({ src => "$webwork_htdocs_url/js/apps/SetMaker/setmaker.js", defer => undef },        '');

	if ($self->r->authz->hasPermissions(scalar($self->r->param('user')), "modify_tags")) {
		print CGI::script({ src => "$ce->{webworkURLs}{htdocs}/js/apps/TagWidget/tagwidget.js" }, '');
		if (open(TAXONOMY, $ce->{webworkDirs}{root} . '/htdocs/DATA/tagging-taxonomy.json')) {
			my $taxo = join("", <TAXONOMY>);
			close TAXONOMY;
			print CGI::script("var taxo = $taxo;");
		} else {
			print CGI::script("var taxo = [];");
			print CGI::script("alert('Could not load the OPL taxonomy from the server.');");
		}
	}

	return '';
}



sub output_CSS {
	my ($self) = @_;
	my $ce = $self->r->ce;
	my $webwork_htdocs_url = $ce->{webwork_htdocs_url};

	print qq!<link href="$webwork_htdocs_url/node_modules/jquery-ui-themes/themes/ui-lightness/jquery-ui.min.css" rel="stylesheet" type="text/css"/>!;

	print CGI::Link({ rel => "stylesheet", href => "$webwork_htdocs_url/js/apps/ImageView/imageview.css" });

	print CGI::Link({ rel => "stylesheet", href => "$webwork_htdocs_url/js/apps/Knowls/knowl.css" });

	return '';

}

sub output_jquery_ui {

    return '';

}



=head1 AUTHOR

Written by John Jones, jj (at) asu.edu.

=cut

1;
