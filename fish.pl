#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'closure';
use Irssi;
use Irssi::Irc;
#use Encode;
use IO::File;
use Crypt::ircBlowfish;

#### TODO:
## Slash commands to make adding/deleting keys easier
## Method of typing in plain text.  Maybe +p by default, like FiSH.
## More stuff?  who knows!
my $blowfish = Crypt::ircBlowfish->new;
my $keyfile = Irssi::get_irssi_dir.'/fish.keys';
my %keys;
# load our fish keys
sub load_keys {
	my $fh = IO::File->new($keyfile, 'r');
	if (!$fh) {
		Irssi::print "Couldn't open $keyfile for reading.";
		return;
	}
	# Clear the hash, incase we're reloading keys.
	%keys = ();
	my $count = 0;
	while (<$fh>) {
		chomp;
		s/^\s+//;
		s/\s+^//;
		next unless length;
		my ($net, $chan, $key) = split /:/, $_;
		$keys{$net}{$chan} = $key;
		$count += 1;
	}
	undef $fh;
	Irssi::print "Loaded keys for $count channels";
	return 0;
}
# save keys
sub save_keys {
	#my $fh = IO::file->new($keyfile, 'w');
	#if (!$fh) {
	#	Irssi::print "Couldn't open $keyfile for writing.";
	#	return;
	#}
	foreach my $net (sort keys %keys) {
		foreach my $chan (sort keys %{$keys{$net}}) {
			my $key = $keys{$net}{$chan};
			Irssi::print "$net:$chan:$key";
		}
	}
}

## Our encrypt/decrypt functions
sub msg_decrypt {
	my ($tag, $chan, $text, $key) = @_;

	if (defined $key and index($text, '+OK') == 0) {
		$blowfish->set_key($key);
		my $text = ( split(/\+OK /, $text) )[1];
		return $blowfish->decrypt($text);
	}
	else {
		# Check if we want to mark unencrypted text or not.
		if (Irssi::settings_get_bool('mark_unencrypted')) {
			my $mark = Irssi::settings_get_str('mark_string');
			return $mark . " " . $text;
		}
		else {
			return $text;
		}
	}
}

sub msg_encrypt {
	my ($tag, $chan, $text, $key) = @_;

	# If we've asked for plain text, just return the text right away.
	# minus the +p
	#if (index($text, $plainprefix) == 0) {
	#	$text =~ s/^$plainprefix//;
	#	return $text;
	#}
	# otherwise, back to normal checking.
	if (defined $key) {
		$blowfish->set_key($key);
		my $eText = "+OK ". $blowfish->encrypt($text);
		return $eText;
	}
	else {
		return $text;
	}
}

## OK, here we'll process the message and decide if it needs decrypting.
# Decrypt other peoples public messages
sub message_public {
	my ($server_rec, $msg, $nick, $addr, $channel) = @_;
	my $tag = $server_rec->{tag};

	## If the key for the tag and channel exists, run through the decryption sub.
	my $key = $keys{$tag}{$channel};
	if (defined $key) {
		# Decrypt the text
		my $text = msg_decrypt($tag, $channel, $msg, $key);
		#$text = Encode::encode("utf8", $text);

		# Continue with the 'message public' signal, albeit a little modified :)
		Irssi::signal_continue(($server_rec, $text, $nick, $addr, $channel));
	}
}

sub event_privmsg {
	my ($server_rec, $args, $nick, $addr) = @_;
	Irssi::print "SVR: $server_rec / ARG: $args / NICK: $nick / ADDR: $addr";
	my ($target, $msg) = split /\s/, $args, 2;
	# if the target is a channel, we can see if we want to decrypt it.
	if ($server_rec->ischannel($target)) {
		Irssi::print "Target '$target' is a channel. MSG: $msg";
		my $tag = $server_rec->{tag};
		my $key = $keys{$tag}{$target};
		if (defined $key) {
			$msg =~ s/^://;		# remove the :, we'll add it later.
			# decrypt the text
			my $dtext = msg_decrypt($tag, $target, $msg, $key);
			# reconstruct the args variable
			my $finalargs = $target . " :" . $dtext;
			# throw it back into the signal, hopefully to be recoded.
			Irssi::signal_continue(($server_rec, $finalargs, $nick, $addr));
		}
	}
}

## Encrypt what we're sending out (hopefully).
sub send_text {
	my ($msg, $server_rec, $witem) = @_;

	# only do this on witem channel
	# we must also make sure that a message exists.  'send text' will trigger if you just press enter on the prompt with nothing there.
	if ($msg and $witem != 0 and $witem->{type} eq "CHANNEL") {
		my $tag = $server_rec->{tag};
		my $channel = $witem->{name};
		my $key = $keys{$tag}{$channel};
		if (defined $key) {
			# Encrypt the text
			my $text = msg_encrypt($tag, $channel, $msg, $key);
	
			# Continue with the signal.
			Irssi::signal_continue(($text, $server_rec, $witem));
		}
	}
}

# decrypt our own public messages, fucking madness, i tell thee.
# This is needed since we encrypted our out going text in 'send_text' and irssi is going to display that string.
sub message_own_public {
	my ($server_rec, $msg, $channel) = @_;
	my $tag = $server_rec->{tag};
	my $key = $keys{$tag}{$channel};
	if (defined $key) {
		my $text = msg_decrypt($tag, $channel, $msg, $key);
		Irssi::signal_continue(($server_rec, $text, $channel));
	}
}
# Handle topic changes
sub message_topic {
	my ($server_rec, $channel, $topic, $nick, $addr) = @_;
	my $tag = $server_rec->{tag};
	my $key = $keys{$tag}{$channel};
	if (defined $key) {
		my $newtopic = msg_decrypt($tag, $channel, $topic, $key);
		Irssi::signal_continue(($server_rec, $channel, $newtopic, $nick, $addr));
	}
}
# the topic bar stuff
sub refresh_topic {
	my ($chanrec) =@_;
	my $current_win = Irssi::active_win()->{active}->{name};
	if (defined $current_win and $current_win eq $chanrec->{name}) {
		#Irssi::statusbar_items_redraw('fishtopicbar');
	}
}
sub get_topic {
	my $type = Irssi::active_win()->{active}->{type};
	if ($type eq "CHANNEL") {
		my $channel = Irssi::active_win()->{active}->{name};
		my $tag = Irssi::active_win()->{active}->{server}->{tag};
		my $topic = Irssi::active_win()->{active}->{topic};
		my $key = $keys{$tag}{$channel};
		if (defined $key) {
			my $newtopic = msg_decrypt($tag, $channel, $topic, $key);
			return $newtopic;
		}
		else {
			return $topic;
		}
	}
	else {
		return "";
	}
}
sub fishtopic_sb {
	my ($item, $get_size_only) = @_;
	my $text = get_topic();
	$item->default_handler($get_size_only, "{topic ".$text."}", undef, 1);
}
# load/unload things for creating/destroying our topic bar item
sub script_unload {
	my ($script, $server_rec, $witem) = @_;
	if ($script =~ /(.*\/)?fish(\.pl)?$/) {
		Irssi::command("STATUSBAR topic REMOVE fishtopic");
		Irssi::command("STATUSBAR topic ADD -after topicbarstart -priority 0 -alignment left topic");
	}
}
sub script_load {
	my ($script, $server_rec, $witem) = @_;
	if ($script =~ /(.*\/)?fish(\.pl)?$/) {
		Irssi::command("STATUSBAR topic REMOVE topic");
		Irssi::command("STATUSBAR topic ADD -after topicbarstart -priority 0 -alignment left fishtopic");
	}
}
# Load our keys
load_keys();
# statusbar item and hooks for the encrypted topics
#Irssi::statusbar_item_register('fishtopic', undef, 'fishtopic_sb');
#Irssi::statusbar_recreate_items();
#Irssi::signal_add_first('command script load', 'script_load');
#Irssi::signal_add_first('command script unload', 'script_unload');
# Some settings
Irssi::settings_add_bool('fish', 'mark_unencrypted' => 1);
Irssi::settings_add_str('fish', 'mark_string', '[u]');
Irssi::settings_add_str('fish', 'plain_prefix', '+p');
# Hook the signals and start some work.
#Irssi::signal_add_first('event privmsg', 'event_privmsg');
#Irssi::signal_add_first('channel topic changed', 'refresh_topic');
Irssi::signal_add_first('message public', 'message_public');
Irssi::signal_add_first('message own_public', 'message_own_public');
#Irssi::signal_add_first('message topic', 'message_topic');
Irssi::signal_add_first('send text', 'send_text');
#Irssi::signal_add_first('server incoming', 'server_incoming');
# A few commands.
Irssi::command_bind('keysave', 'save_keys');
Irssi::command_bind('keyload', 'load_keys');
