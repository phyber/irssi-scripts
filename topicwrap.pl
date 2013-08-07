# run this commands before loading the script
# /statusbar topic_wrap enable
# /statusbar topic_wrap add topic_wrap
# see /help statusbar for infos about changing the statusbar position

use Irssi::Irc;
use Irssi 20020217; # Irssi 0.8.0
use 5.6.0;
use vars qw($VERSION %IRSSI);
$VERSION = "1.2";
%IRSSI = (
    authors     => "Valentin Batz",
    contact     => 'vb\@g-23.org',
    name        => "topicwrap",
    description => "shows a 2nd topic bar when the topic is longer than window width",
    license     => "GPLv2",
    url		=> "http://hurzelgnom.homepage.t-online.de/irssi/scripts/",
    sbitems     => "topic_wrap",
);
use Irssi::TextUI;
use strict;

our $topic_wrap = '';
our $term_resizing = 0;
# taken from title.pl, i don't want to reinvent the wheel :)
sub topic_str {
	my $server = Irssi::active_server();
	my $topic;
	my $item = ref Irssi::active_win() ? Irssi::active_win()->{active} : '';
	if(ref $server && ref $item && $item->{type} eq 'CHANNEL') {
		$topic = $item->{topic};
		# Remove colour and bold from topic...
		$topic =~ s/\003(\d{1,2})(\,(\d{1,2})|)//g;
		$topic =~ s/[\x00-\x1f]//g;
		return $topic if length $topic;
	}
	return '';
}
# idea from dccstat.pl                                                                                                      
sub topic_refresh {
	my $tlen = length($topic_wrap);
	if ($tlen > 0) {
		Irssi::command('statusbar topic_wrap enable');
	} else {
		Irssi::command('statusbar topic_wrap disable');
	}
	Irssi::statusbar_items_redraw('topic_wrap');
}

sub update_topic {
	my $indent = Irssi::settings_get_int('topicwrap_indent');
	my $window = Irssi::active_win;
	my $width = $window->{'width'};
	my $space = ' ' x $indent;
	my $realtopic = topic_str();
	my $tlen = length($realtopic);
	if ($tlen > $width - $indent) {
		my $topic_tmp = substr($realtopic, $width-1 - $indent);
		$tlen = length($topic_tmp);
		if ($tlen > $width) {
			$topic_wrap = $space . substr($topic_tmp, $indent, $width);
		} else {
			$topic_wrap = $space . substr($topic_tmp, $indent);
		}
	} else {
		$topic_wrap = '';
	}
	topic_refresh();
	$term_resizing = 0;
}
# idea from nicklist.pl, it delays the update a little so the statusbar will be 
# drawn properly
sub term_resized {
	if ($term_resizing) {
		return;
	}
	$term_resizing = 1;
	Irssi::timeout_add_once(10, \&update_topic, []);
}

sub topic_wrap_sb {
        my ($item, $get_size_only) = @_;
	$item->default_handler($get_size_only, "$topic_wrap", "", 1);
}
# idea from trigger.pl, it will disable the topic_wrap statusbar if you unload 
# the script
sub script_unload {
	my $script = shift;
	if ($script =~ /(.*\/)?topicwrap(\.pl)?$/ ) {
		Irssi::command('statusbar topic_wrap disable');
	}
}

Irssi::statusbar_item_register('topic_wrap', "", 'topic_wrap_sb');

Irssi::signal_add("window changed", \&update_topic);
Irssi::signal_add("window item changed", \&update_topic);
Irssi::signal_add("channel topic changed", \&update_topic);
Irssi::signal_add("terminal resized", \&term_resized);
Irssi::signal_add("setup changed", \&update_topic);
Irssi::signal_add_first("command script unload", \&script_unload);
Irssi::settings_add_int('topicwrap', 'topicwrap_indent', 0);
update_topic();
