#!/usr/bin/perl

use strict;
use warnings;

# include modules
use File::Basename qw(basename);

use lib './lib';
use HTML::Template;
use SQL;
require 'cgidec.pl';
require 'date.pl';
require 'kscconf.pl';
require 'security.pl';

# script file name
my $myname = basename($0, '');

# generate absolute uri
my $absuri = '';
if ($ENV{'SERVER_PORT'} == 443) {
	$absuri .= 'https://'
} else {
	$absuri .= 'http://'
}

if ($ENV{'SERVER_NAME'} ne '') {
	$absuri .= $ENV{'SERVER_NAME'};
} else {
	$absuri .= $ENV{'HTTP_HOST'};
}

$absuri .= $ENV{'REQUEST_URI'};

my $abspath = $absuri;
$abspath =~ s/$myname.+$//;

# constants, default values
my $VER = '0.3.1';
my %vars = ( 'SiteName'=>'KeiSpade','SiteDescription'=>'The Multimedia Wiki','ScriptName'=>$myname,'UploaderName'=>'upload.pl',
             'ScriptAbsolutePath'=>$abspath, 'SidebarPagesListLimit'=>'10','ContentLanguage'=>'ja' );
%vars = (%vars, &kscconf::load('./dat/kspade.conf'));

# http header + html meta header
my $httpstatus = "Status: 200 OK";
my $contype = "Content-Type: text/html; charset=UTF-8";
my $htmlhead = '<meta charset=utf-8 /><link href="./css/kspade.css" rel="stylesheet" type="text/css" media="screen,print">';
$htmlhead .= "<link rel=\"contents\" href=\"./$vars{'ScriptName'}?cmd=search\">";
$htmlhead .= "<link rel=\"start\" href=\"./$vars{'ScriptName'}?page=TopPage\">";
$htmlhead .= "<link rel=\"index\" href=\"./$vars{'ScriptName'}?cmd=category\">";

my ($htmlbdhd, $htmlbody, $sidebar, $htmlfoot) = ( '', '', '', '');

# process cgi args
my %query = &getline($ENV{'QUERY_STRING'});

&setpagename($query{'page'});

sub setpagename {
	$vars{'PageName'} = &exorcism($_[0]);
	if (not defined $vars{'PageName'} or not $vars{'PageName'} =~ /.+/) {
		$vars{'PageName'} = 'TopPage'
	}
	$vars{'NoSpacePageName'} = $vars{'PageName'};
	$vars{'NoSpacePageName'} =~ tr/ /+/;
}

# connect to DB
my $database = './dat/kspade.db';
my $data_source = "dbi:SQLite:dbname=$database";
my $sql = SQL->new($data_source);

if ($sql->tableexists == 0) {
	# database initialize (create the table)
	$sql->create_table;
	my $modified_date = time();
	my $created_date = $modified_date;
	my $body = &tmpl2html('html/tutorial.txt',\%vars);
	$sql->do("insert into pages (title,lastmodified_date,created_date,tags,autotags,copyright,body)
		values ('TopPage','$modified_date','$created_date','Help','Help','Copyleft','$body');");
	$htmlhead .= '<link href="./css/light.css" rel="stylesheet" type="text/css">';
	$htmlhead .= '<title>Miracle! Table was created!</title>';
	$htmlbody .= '<p>Table was created. Please reload.</p>';
}

$htmlbdhd .= &tmpl2html('html/bodyhead.html',\%vars);



if ((not defined $query{'cmd'}) and (defined $vars{'PageName'})) {
	&page;
} elsif (defined $query{'cmd'}) {
	no strict 'refs';
	&{$query{'cmd'}};
}


# print page
sub page { 
	my @res = ($sql->fetch("select * from pages where title='".$vars{'PageName'}."';"));
	if (defined $res[0]) {
		my $modified = $res[1];
		my $created  = $res[2];
		chop $res[3];

		$modified = &relative_time($modified);
		$created = &relative_time($created);

		$htmlhead .= '<title>'.$res[0].'@'.$vars{'SiteName'}.'</title>';

		require 'Text/HatenaEx.pm';
		$htmlbody .= "<h2>$res[0]</h2>";
		my $parsed .= Text::HatenaEx->parse(&noscript($res[7]));
		$htmlbody .= $parsed;

		my $confer;
		if (defined $res[5]) {
			my @filedatas= split(/\]\[/, $res[5]);
			foreach my $filedata (@filedatas) {
				my @elements = split(/\//, $filedata);
				$confer .= "<a href=\"files/$elements[0]\">$elements[1]</a> [<a href=\"./$vars{'ScriptName'}?&page=$vars{'PageName'}&amp;filename=$elements[0]&amp;cmd=delupload\" rel=\"nofollow\">X</a>] ";
				$confer =~ s/[\[\]]+//g;
			}
	

			my $filenum = @filedatas;
			$htmlbody .= '</section><section><h2>Attached File</h2>'.$confer.'</section>' if $filenum == 1;
			$htmlbody .= '</section><section><h2>Attached Files</h2>'.$confer.'</section>' if $filenum > 1;
		}
		$vars{'MetaInfo'} = "Last-modified: $modified, Created: $created, Tags: $res[3], AutoTags: $res[4]<br />$res[6]<br />";
	} else {
		$htmlhead .= '<title>Not Found'.'@'.$vars{'SiteName'}.'</title>';
		$httpstatus = 'Status: 404 Not Found';
	}
} 
sub edit {
# print edit page form
	my @res = ($sql->fetch("select body from pages where title='$vars{'PageName'}';"));
	#$res[0] =~ s/<br \/>/\n/g;
	$vars{'DBody'} = $res[0];
	require 'sha.pl';
	$vars{'BodyHash'} = &sha::pureperl($res[0]);
	#$vars{'Token'} = rand)
	$htmlhead .= '<meta http-equiv="Pragma" content="no-cache">';
	$htmlhead .= '<title>'.$vars{'PageName'}.' &gt; Edit@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/editbody.html',\%vars);
	delete $vars{'DBody'};
} 
sub post {
# submit edited text
	my $pagename = $vars{'PageName'};



	if ($ENV{'REQUEST_METHOD'} eq 'POST') {
		my %page = &fetch2edit();
		require 'sha.pl';
		my @res = ($sql->fetch("select * from pages where title='".$vars{'PageName'}."';"));
		my $hashparent = &sha::pureperl($res[7]);
		if (($page{'bodyhash'} eq $hashparent) or ($page{'bodyhash'} =~ /Conflict/)) {
			$page{'title'} = 'undefined'.rand(16384) if $page{'title'} eq '';
			$sql->do("update pages set title='$page{'title'}', lastmodified_date='$page{'modified_date'}', tags='$page{'tags'}',
				autotags='$page{'autotags'}', copyright='$page{'copyright'}', body='$page{'body'}' where title='".$vars{'PageName'}."';");
			if ($pagename eq $page{'title'}) {
				&setpagename($page{'title'});
				&page;
			}
		} else {
			require Text::Diff;
			my $diff = Text::Diff::diff(\$res[7],\$page{'body'});
			$diff =~ s/\n/<br \/>/g;
			$vars{'Diff'} = $diff;
			$vars{'Body'} = $res[7];
			$vars{'DBody'} = $page{'body'};
			$htmlhead .= '<title>'.$vars{'PageName'}.' &gt; Error@'.$vars{'SiteName'}.'</title>';
			$htmlbody .= &tmpl2html('html/conflict.html',\%vars);
			delete $vars{'Diff'};
			delete $vars{'Body'};
		}
		$httpstatus = 'Status: 303 See Other';
		$httpstatus .= "\nLocation: $vars{'ScriptAbsolutePath'}$vars{'ScriptName'}?page=$vars{'PageName'}";
	}
} 
sub preview {
# submit edited text
	my $pagename = $vars{'PageName'};

	my %page = &fetch2edit();
	if ($pagename eq $page{'title'}) {
		&setpagename($page{'title'});
		&page;
	}

	$htmlhead .= '<title>'.$page{'title'}.'@'.$vars{'SiteName'}.'</title>';

	require 'Text/HatenaEx.pm';
	$htmlbody .= "<h2>$page{'title'}</h2>";
	my $parsed .= Text::HatenaEx->parse(&noscript($page{'body'}));
	$htmlbody .= $parsed;
} 
sub new {
# print new page form
	$htmlhead .= '<meta http-equiv="Pragma" content="no-cache">';
	$htmlhead .= '<title> New@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/newbody.html',\%vars);
}
sub newpost {
# submit new page
	if ($ENV{'REQUEST_METHOD'} eq 'POST') {
		my %page = &fetch2edit();
		my @res = ($sql->fetch("select count(*) from pages where title='".$page{'title'}."';"));
		$page{'title'} = $page{'title'}.rand(16384) unless $res[0] == 0;
		$page{'title'} = 'undefined'.rand(16384) if $page{'title'} eq '';
		$vars{'PageName'} = $page{'title'};
		$sql->do("insert into pages (title,lastmodified_date,created_date,tags,autotags,copyright,body)
			values ('$page{'title'}','$page{'created_date'}','$page{'created_date'}','$page{'tags'}','$page{'autotags'}','$page{'copyright'}','$page{'body'}');");
		&setpagename($vars{'PageName'});
		$httpstatus = 'Status: 303 See Other';
		$httpstatus .= "\nLocation: ${abspath}$vars{'ScriptName'}?page=$vars{'PageName'}";
		#&page;
	}
}
sub del {
# print delete confirm
	$htmlhead .= '<title>'.$vars{'PageName'}.' &gt; Delete@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/delete.html',\%vars);
}
sub delpage {
# delete page
	if ($ENV{'REQUEST_METHOD'} eq 'POST') {
		$sql->do("delete from pages where title='".$vars{'PageName'}."'");
	}
	$htmlhead .= '<title>'.$vars{'PageName'}.' &gt; Deleted@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/deleted.html',\%vars);
}
sub search {
	my $query = &htmlexor($query{'query'});
	$query =~ s/\s/AND/g if defined $query;
	$vars{'Query'} = $query{'query'};
	if (defined $query{'query'}) {
		# normal search
		$vars{'PagesList'} = &listpages("select title from pages where body like '%$query%';"
			,"<a href=\"./$vars{'ScriptName'}?page=%s\">%s</a><br />");
		$htmlhead .= '<title>Search &gt; Body@'.$vars{'SiteName'}.'</title>';
		$htmlbody .= &tmpl2html('html/search.html',\%vars);
		delete $vars{'PagesList'};

	} else {
		# print all pages
		$vars{'PagesList'} = &listpages("select title from pages;"
			,"<a href=\"./$vars{'ScriptName'}?page=%s\">%s</a><br />");
		$htmlhead .= '<title>PagesList@'.$vars{'SiteName'}.'</title>';
		$htmlbody .= &tmpl2html('html/list.html',\%vars);
		delete $vars{'PagesList'};
	}
	delete $vars{'Query'};

} 
sub category {
	# print categories
	my $query = &htmlexor($query{'query'});
	$query =~ s/\s/AND/g;
	$vars{'Query'} = $query{'query'};
	if ($vars{'Query'} eq '') {
		$vars{'CategoryTitle'} = "Index of Categories";
		$vars{'CategoryList'} = '<ul>';
		$vars{'CategoryList'} .= &listcategory("select tags from pages;"
		,"<li><a href=\"./$vars{'ScriptName'}?cmd=category&amp;query=%s\">%s</a></li>");
		$vars{'CategoryList'} .= '</ul>';
	} else {
		$vars{'CategoryTitle'} = "Pages related to '$vars{'Query'}'";
		$vars{'CategoryList'} = &listcategory("select title from pages where tags like '%$query%';"
			,"<a href=\"./$vars{'ScriptName'}?page=%s\">%s</a><br />");
	}
	$htmlhead .= '<title>Search &gt; Category@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/category.html',\%vars);
	delete $vars{'CategoryTitle'};
	delete $vars{'CategoryList'};
	delete $vars{'Query'};

} 
sub upload {
	# print upload form
	$htmlhead .= '<title>'.$vars{'PageName'}. ' &gt; Upload@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/upload.html',\%vars);

} 
sub delupload {
# print delete confirm
	my $filename = &htmlexor($query{'filename'});
	$vars{'DeleteFileName'} = $filename;
	#$vars{'PagesList'} = &listpages("select title from pages where confer like '%$filename%';");
	my @pages = $sql->fetch("select title from pages where confer like '%$filename%';");
	$vars{'PagesList'} = &listpages("select title from pages where confer like '%$filename%';"
		,"<a href=\"./$vars{'ScriptName'}?page=%s\">%s</a><br />");
	$htmlhead .= '<title>'.$filename. ' &gt; Delete Uploaded Files@'.$vars{'SiteName'}.'</title>';
	$htmlbody .= &tmpl2html('html/delupload.html',\%vars);
}

sub delfile {
	if ($ENV{'REQUEST_METHOD'} eq 'POST') {
	my $filename = &htmlexor($query{'filename'});
	my @pages = $sql->fetch("select title from pages where confer like '%$filename%';",0);
	foreach my $tmp (@pages) {
		my @files = $sql->fetch("select confer from pages where title='$tmp';");
		$files[0] =~ s/\[$filename\/.+?\]//g;
		unlink('./files/'.$filename);
		my $modifieddate = time();
		$sql->do("update pages set lastmodified_date='$modifieddate', confer='$files[0]' where title='$tmp';");
	}
	&setpagename($vars{'PageName'});
	&page;
	}
}

sub addfile {
	# submit file
	my %page = &fetch2edit();

	$htmlhead .= '<title>'.$vars{'PageName'}. ' &gt; UploadProcess@'.$vars{'SiteName'}.'</title>';
	my $filename = &htmlexor($query{'filename'});
	my $original = &htmlexor($query{'orig'});
	my @res = ($sql->fetch("select confer from pages where title='$vars{'PageName'}';"));
	my $files = $res[0];
	if ($files =~ /$filename/) {

	} else {
		my $tmp  = &spridate('%04d %2d %2d %2d:%02d:%02d');
		$files .= "[$filename/$original($tmp)]";
		$sql->do("update pages set lastmodified_date='$page{'modified_date'}', confer='$files' where title='$vars{'PageName'}';");
	}
	# TODO: これはあくまで暫定処置 いずれ全体的な構造を見直す
	$htmlbody = "";
	$sidebar = "";
}

$vars{'SidebarCategoryList'} = &listcategory("select tags from pages;"
	,"<dd><a href=\"./$vars{'ScriptName'}?cmd=category&amp;query=%s\">%s</a></dd>");
$vars{'SidebarPagesList'} = &listpages("select title from pages order by lastmodified_date desc, title limit $vars{'SidebarPagesListLimit'};"
	,"<dd><a href=\"./$vars{'ScriptName'}?page=%s\">%s</a></dd>");
$sidebar  = &tmpl2html('html/sidebar.html',\%vars);
$htmlfoot = &tmpl2html('html/bodyfoot.html',\%vars);
print "$httpstatus\n$contype\n\n";
print '<!DOCTYPE html><html lang="'.$vars{'ContentLanguage'}.'"><head>'.$htmlhead.'</head><body><header>'.$htmlbdhd.'</header>
       <div id="container"><div id="main_container"><section>'.$htmlbody.'</section><hr /></div><aside><dl id="page_menu">'.$sidebar.'</dl></aside></div>
       <footer>'.$htmlfoot.'</footer>';
print "</body></html>";


# ページ編集・作成用共通サブルーチン
sub fetch2edit {
	my %args = ();
	read (STDIN, my $postdata, $ENV{'CONTENT_LENGTH'});
	my %form = &getline($postdata);

	$args{'title'} = &textalize(&exorcism($form{'title'}));
	$args{'modified_date'} = time();
	$args{'created_date'} = time();
	$args{'tags'} = '';
	$args{'autotags'} = '';
	$args{'confer'} = '';
	$args{'copyright'} = '';
	$args{'body'} = &exorcism($form{'body'});
	$args{'bodyhash'} = &exorcism($form{'bodyhash'});

	$args{'title'} =~ s/ +$//;

	my $tagstr = $args{'title'};
	if (defined $tagstr) {
		$tagstr =~ s/^\[(.+)\](.+)/$1/g;
		if (defined $2) {
			my @tagstrs= split(/\]\[/, $tagstr);
			foreach my $tag (@tagstrs) {
				$tag =~ s/[\[\]]+//g;
				$args{'tags'} .= $tag.'|';
			}
		}
	}

	chomp(%args);
	return(%args);
}

sub listpages {
	my @res = ($sql->fetch($_[0],0));
	my $pageslist;
	my $format = $_[1];
	foreach my $tmp (@res) {
		my $formatmp = $format;
		$formatmp =~ s/%s/$tmp/g;
		$pageslist .= $formatmp;
	}
	return $pageslist;
}

sub listcategory {
	my @res = ($sql->fetch($_[0],0));
	my $categorylist;
	my $format = $_[1];
	my %category;
	foreach my $tmp (@res) {
		my @tags = split(/\|/, $tmp);
		foreach my $tag (@tags) {
			my $formatmp = $format;
			$formatmp =~ s/%s/$tag/g;
			$categorylist .= $formatmp if not exists $category{$tag};
			$category{$tag} = 1;
		}
	}
	return $categorylist;
}

sub tmpl2html {
	my $template = HTML::Template->new(filename => $_[0],die_on_bad_params => 0,cache => 1);
	$template->param(%{$_[1]});
	return $template->output;
}

sub relative_time {
	my $elapsed = time() - $_[0];

	if ($elapsed <= 86400) {
		return 'Today '.spritimearg('%02d:%02d:%02d',$_[0])
	} elsif ($elapsed > 86400 and $elapsed <= 172800) {
		return 'Yesterday '.spritimearg('%02d:%02d:%02d',$_[0])
	} else {
		return spridatearg('%04d/%02d/%02d',$_[0])
		.' '.spritimearg('%02d:%02d:%02d',$_[0]);
	}

}


