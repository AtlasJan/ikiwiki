#!/usr/bin/perl
# -*- cperl-indent-level: 8; -*-
# Ikiwiki parentlinks plugin.
package IkiWiki::Plugin::parentlinks;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "pagetemplate", id => "parentlinks", call => \&pagetemplate);
} # }}}

sub parentlinks ($) { #{{{
	my $page=shift;

	my @ret;
	my $path="";
	my $title=$config{wikiname};
	my $i=0;
	my $depth=0;
	my $height=0;

	my @pagepath=(split("/", $page));
	my $pagedepth=@pagepath;
	foreach my $dir (@pagepath) {
		next if $dir eq 'index';
		$depth=$i;
		$height=($pagedepth - $depth);
		push @ret, {
			    url => urlto($path, $page),
			    page => $title,
			    depth => $depth,
			    height => $height,
			    "depth_$depth" => 1,
			    "height_$height" => 1,
			   };
		$path.="/".$dir;
		$title=IkiWiki::pagetitle($dir);
		$i++;
	}
	return @ret;
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	if ($template->query(name => "parentlinks")) {
		$template->param(parentlinks => [parentlinks($page)]);
	}
} # }}}

1
