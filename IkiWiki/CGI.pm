#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use IkiWiki::UserInfo;
use open qw{:utf8 :std};
use Encode;

sub printheader ($) { #{{{
	my $session=shift;
	
	if ($config{sslcookie}) {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-httponly => 1, -secure => 1));
	} else {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-httponly => 1));
	}
} #}}}

sub showform ($$$$;@) { #{{{
	my $form=shift;
	my $buttons=shift;
	my $session=shift;
	my $cgi=shift;

	if (exists $hooks{formbuilder}) {
		run_hooks(formbuilder => sub {
			shift->(form => $form, cgi => $cgi, session => $session,
				buttons => $buttons);
		});
	}

	printheader($session);
	print misctemplate($form->title, $form->render(submit => $buttons), @_);
}

sub redirect ($$) { #{{{
	my $q=shift;
	my $url=shift;
	if (! $config{w3mmode}) {
		print $q->redirect($url);
	}
	else {
		print "Content-type: text/plain\n";
		print "W3m-control: GOTO $url\n\n";
	}
} #}}}

sub decode_cgi_utf8 ($) { #{{{
	# decode_form_utf8 method is needed for 5.10
	if ($] < 5.01) {
		my $cgi = shift;
		foreach my $f ($cgi->param) {
			$cgi->param($f, map { decode_utf8 $_ } $cgi->param($f));
		}
	}
} #}}}

sub decode_form_utf8 ($) { #{{{
	if ($] >= 5.01) {
		my $form = shift;
		foreach my $f ($form->field) {
			$form->field(name  => $f,
			             value => decode_utf8($form->field($f)),
		                     force => 1,
			);
		}
	}
} #}}}

# Check if the user is signed in. If not, redirect to the signin form and
# save their place to return to later.
sub needsignin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	if (! defined $session->param("name") ||
	    ! userinfo_get($session->param("name"), "regdate")) {
		$session->param(postsignin => $ENV{QUERY_STRING});
		cgi_signin($q, $session);
		cgi_savesession($session);
		exit;
	}
} #}}}	

sub cgi_signin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	decode_cgi_utf8($q);
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "signin",
		name => "signin",
		charset => "utf-8",
		method => 'POST',
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		header => 0,
		template => {type => 'div'},
		stylesheet => baseurl()."style.css",
	);
	my $buttons=["Login"];
	
	if ($q->param("do") ne "signin" && !$form->submitted) {
		$form->text(gettext("You need to log in first."));
	}
	$form->field(name => "do", type => "hidden", value => "signin",
		force => 1);
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);

	if ($form->submitted) {
		$form->validate;
	}

	showform($form, $buttons, $session, $q);
} #}}}

sub cgi_postsignin ($$) { #{{{
	my $q=shift;
	my $session=shift;
	
	# Continue with whatever was being done before the signin process.
	if (defined $session->param("postsignin")) {
		my $postsignin=CGI->new($session->param("postsignin"));
		$session->clear("postsignin");
		cgi($postsignin, $session);
		cgi_savesession($session);
		exit;
	}
	else {
		error(gettext("login failed, perhaps you need to turn on cookies?"));
	}
} #}}}

sub cgi_prefs ($$) { #{{{
	my $q=shift;
	my $session=shift;

	needsignin($q, $session);
	decode_cgi_utf8($q);
	
	# The session id is stored on the form and checked to
	# guard against CSRF.
	my $sid=$q->param('sid');
	if (! defined $sid) {
		$q->delete_all;
	}
	elsif ($sid ne $session->id) {
		error(gettext("Your login session has expired."));
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "preferences",
		name => "preferences",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		validate => {
			email => 'EMAIL',
		},
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		template => {type => 'div'},
		stylesheet => baseurl()."style.css",
		fieldsets => [
			[login => gettext("Login")],
			[preferences => gettext("Preferences")],
			[admin => gettext("Admin")]
		],
	);
	my $buttons=["Save Preferences", "Logout", "Cancel"];
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);
	
	$form->field(name => "do", type => "hidden", value => "prefs",
		force => 1);
	$form->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$form->field(name => "email", size => 50, fieldset => "preferences");
	
	my $user_name=$session->param("name");

	# XXX deprecated, should be removed eventually
	$form->field(name => "banned_users", size => 50, fieldset => "admin");
	if (! is_admin($user_name)) {
		$form->field(name => "banned_users", type => "hidden");
	}
	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
		if (is_admin($user_name)) {
			my $value=join(" ", get_banned_users());
			if (length $value) {
				$form->field(name => "banned_users", force => 1,
					value => join(" ", get_banned_users()),
					comment => "deprecated; please move to banned_users in setup file");
			}
			else {
				$form->field(name => "banned_users", type => "hidden");
			}
		}
	}
	
	if ($form->submitted eq 'Logout') {
		$session->delete();
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Cancel') {
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Save Preferences' && $form->validate) {
		if (defined $form->field('email')) {
			userinfo_set($user_name, 'email', $form->field('email')) ||
				error("failed to set email");
		}

		# XXX deprecated, should be removed eventually
		if (is_admin($user_name)) {
			set_banned_users(grep { ! is_admin($_) }
					split(' ',
						$form->field("banned_users"))) ||
				error("failed saving changes");
			if (! length $form->field("banned_users")) {
				$form->field(name => "banned_users", type => "hidden");
			}
		}

		$form->text(gettext("Preferences saved."));
	}
	
	showform($form, $buttons, $session, $q);
} #}}}

sub check_banned ($$) { #{{{
	my $q=shift;
	my $session=shift;

	my $name=$session->param("name");
	if (defined $name) {
		# XXX banned in userinfo is deprecated, should be removed
		# eventually, and only banned_users be checked.
		if (userinfo_get($session->param("name"), "banned") ||
		    grep { $name eq $_ } @{$config{banned_users}}) {
			print $q->header(-status => "403 Forbidden");
			$session->delete();
			print gettext("You are banned.");
			cgi_savesession($session);
			exit;
		}
	}
}

sub cgi_getsession ($) { #{{{
	my $q=shift;

	eval q{use CGI::Session};
	error($@) if $@;
	CGI::Session->name("ikiwiki_session_".encode_utf8($config{wikiname}));
	
	my $oldmask=umask(077);
	my $session = eval {
		CGI::Session->new("driver:DB_File", $q,
			{ FileName => "$config{wikistatedir}/sessions.db" })
	};
	if (! $session || $@) {
		error($@." ".CGI::Session->errstr());
	}
	
	umask($oldmask);

	return $session;
} #}}}

sub cgi_savesession ($) { #{{{
	my $session=shift;

	# Force session flush with safe umask.
	my $oldmask=umask(077);
	$session->flush;
	umask($oldmask);
} #}}}

sub cgi (;$$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI};
	error($@) if $@;
	$CGI::DISABLE_UPLOADS=$config{cgi_disable_uploads};

	if (! $q) {
		binmode(STDIN);
		$q=CGI->new;
		binmode(STDIN, ":utf8");
	
		run_hooks(cgi => sub { shift->($q) });
	}

	my $do=$q->param('do');
	if (! defined $do || ! length $do) {
		my $error = $q->cgi_error;
		if ($error) {
			error("Request not processed: $error");
		}
		else {
			error("\"do\" parameter missing");
		}
	}
	
	# Need to lock the wiki before getting a session.
	lockwiki();
	loadindex();
	
	if (! $session) {
		$session=cgi_getsession($q);
	}
	
	# Auth hooks can sign a user in.
	if ($do ne 'signin' && ! defined $session->param("name")) {
		run_hooks(auth => sub {
			shift->($q, $session)
		});
		if (defined $session->param("name")) {
			# Make sure whatever user was authed is in the
			# userinfo db.
			if (! userinfo_get($session->param("name"), "regdate")) {
				userinfo_setall($session->param("name"), {
					email => "",
					password => "",
					regdate => time,
				}) || error("failed adding user");
			}
		}
	}
	
	check_banned($q, $session);
	
	run_hooks(sessioncgi => sub { shift->($q, $session) });

	if ($do eq 'signin') {
		cgi_signin($q, $session);
		cgi_savesession($session);
	}
	elsif ($do eq 'prefs') {
		cgi_prefs($q, $session);
	}
	elsif (defined $session->param("postsignin") || $do eq 'postsignin') {
		cgi_postsignin($q, $session);
	}
	else {
		error("unknown do parameter");
	}
} #}}}

# Does not need to be called directly; all errors will go through here.
sub cgierror ($) { #{{{
	my $message=shift;

	print "Content-type: text/html\n\n";
	print misctemplate(gettext("Error"),
		"<p class=\"error\">".gettext("Error").": $message</p>");
	die $@;
} #}}}

1
