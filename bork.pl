#!/usr/bin/env perl
use strict;
use warnings;
use Irssi;
use Irssi::Irc;

my $ACTIVE_CHAN = '#borkenbork';

my %replace_map = (
	'aa' => "\xc3\xa5", # å 
	'ae' => "\xc3\xa4", # ä 
	'oe' => "\xc3\xb6", # ö 
	'AA' => "\xc3\x85", 
	'AE' => "\xc3\x84", 
	'OE' => "\xc3\x96", 
);

sub text_replace {
	my $text = shift;
	while (my ($key, $value) = each(%replace_map)) {
		$text =~ s/$key/$value/gs;
	}
	return $text;
}

sub send_text {
	my ($msg, $server_rec, $witem) = @_;

	# only do this on witem channel
	# we must also make sure that a message exists.  'send text' will trigger if you just press enter on the prompt with nothing there.
	if ($msg and $witem != 0 and $witem->{type} eq 'CHANNEL') {
		my $tag = $server_rec->{tag};
		my $channel = $witem->{name};
		if ($channel eq $ACTIVE_CHAN) {
			my $text = text_replace($text);
			Irssi::signal_continue(($text, $server_rec, $witem));
		}
	}
}

# Hook the signals and start some work.
Irssi::signal_add_first('send text', 'send_text');
