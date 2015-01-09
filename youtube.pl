########
## youtube.pl
########
# Adds the video title to any youtube urls that you paste into a channel.
########
# Required Modules:
#   LWP::UserAgent
#   HTML::TokeParser
########
# Example:
# You type:
#   <You> Hey guys, have you seen this?  http://www.youtube.com/watch?v=8HE9OQ4FnkQ
# You get in the channel:
#   <You> Hey guys, have you seen this?  http://www.youtube.com/watch?v=8HE9OQ4FnkQ (Take On Me: Literal Video Version *ORIGINAL*)
########
# :)
########
use strict;
use warnings;
use Irssi;
use LWP::UserAgent;
use HTML::TokeParser;

use vars qw($VERSION %IRSSI);
$VERSION = "1.2";
%IRSSI = (
	authors		=> "David O'Rourke",
	contact		=> "phyber @ #irssi",
	name		=> "youtube.pl",
	description	=> "Add the title of a video to any youtube links you paste.",
	license		=> "GPLv2",
	changed		=> "2009/11/19",
);

use constant {
	INVALID		=> 0,
	VALID_CHANNEL	=> 1,
	VALID_QUERY	=> 2,

	YOUTUBE_PATTERN		=> qr/^(http(s?):\/\/)(www\.)?youtube\.com\/watch\?v=(.*)$/,
	YOUTUBE_SHORTLINK	=> "http://youtu.be/",
};

##
sub get_youtube_title {
	my ($url) = @_;

	# Get a user agent
	my $ua = LWP::UserAgent->new;

	# Set the UserAgent of the UserAgent
	my $agent = Irssi::settings_get_str('youtube_useragent');
	my $timeout = Irssi::settings_get_int('youtube_timeout');
	$ua->agent($agent." ");
	$ua->timeout($timeout);

	# OK, now go and get the page and let the magic happen
	my $response = $ua->get($url);
	if (!$response->is_success) {
		Irssi::print "Failed to fetch page for YouTube URL: $url";
		return undef;
	}

	my $p = HTML::TokeParser->new(\$response->content);
	if (!$p->get_tag("title")) {
		Irssi::print "Failed to get title for YouTube URL: $url";
		return undef;
	}

	# Strip youtube prefix/suffix.
	my $title = $p->get_trimmed_text;
	$title =~ s/YouTube\s- //;
	$title =~ s/\s-\sYouTube//;
	return $title;
}

sub is_valid_source {
	my ($witem) = @_;

	if (!defined $witem) {
		return INVALID;
	}

	my $wtype = $witem->{type};

	return ($wtype eq "CHANNEL" or $wtype eq "QUERY");
}

sub is_valid_chan {
	my ($wtype, $channel, $tag) = @_;

	# First a quick check to see if this is a query and if we are enabled
	# for ALL queries
	if ($wtype eq "QUERY" and Irssi::settings_get_bool('youtube_queries')) {
		return VALID_QUERY;
	}

	# Otherwise, check to see if we're on a valid channel.
	foreach my $tc (split / /, Irssi::settings_get_str('youtube_channels')) {
		my ($t, $c) = split /:/, $tc;

		# We should always have at least $t, so lc it here.
		$t = lc $t;

		# Now we check if $c is defined.  if it's not, we should have
		# a nick or channel in $t
		if (!defined $c) {
			if ($t eq $channel) {
				return VALID_CHANNEL;
			}
		}
		else {
			# lc $c here since it could be undefined above.
			$c = lc $c;
			if (($t eq $tag) and ($c eq $channel)) {
				return VALID_CHANNEL;
			}
		}
	}

	return 0;
}

sub process_send_text {
	my ($msg, $server_rec, $witem) = @_;
	my $wtype = $witem->{type};

	if (!defined $msg or !is_valid_source($witem)) {
		return;
	}

	my $tag = lc $server_rec->{tag};
	my $channel = lc $witem->{name};

	# Check if we want to run in this tag and channel
	if (!is_valid_chan($wtype, $channel, $tag)) {
		return;
	}

	# Break the words out into an array and count the number of words.
	my @words = split / /, $msg;
	my $num_words = scalar @words;

	# Loop over all of the words that we got, checking to see if any of
	# them look like a youtube URL.
	for (my $i = 0; $i < $num_words; $i++) {
		# Grab the current word
		my $w = $words[$i];

		# Check it for signs of youtube.
		my (undef, undef, undef, $vid) = $w =~ YOUTUBE_PATTERN;
		if (!defined $vid) {
			next;
		}

		# Attempt to get page title from youtube page.
		my $title = get_youtube_title($w);
		if (!defined $title) {
			next;
		}

		# Check if we wanted to use a shortlink.
		if (Irssi::settings_get_bool('youtube_shortlink')) {
			($vid, my $discard) = split /\&/, $vid;
			$w = YOUTUBE_SHORTLINK . $vid;
		}

		# If we got the title, also check if we wanted to make
		# it a HD link
		if (Irssi::settings_get_bool('youtube_hdlink')) {
			if (!($w =~ m/fmt=18/)) {
				$w = $w."&fmt=18";
			}
		}

		# Overwrite the word in the array with our new
		# youtube information.
		my $new_text = "$w ($title)";
		$words[$i] = $new_text;
	}
	Irssi::signal_continue((join(' ', @words), $server_rec, $witem));
}

sub usage {
	# If we haven't got any channels set, print the usage.
	if (Irssi::settings_get_str('youtube_channels') eq '') {
		Irssi::print "youtube.pl v$VERSION";
		Irssi::print "";
		Irssi::print "CONFIG EXAMPLES";
		Irssi::print "";
		Irssi::print "Add channels to run in with:";
		Irssi::print "  /set youtube_channels tag:#channel";
		Irssi::print "";
		Irssi::print "The scripts useragent can be set with:";
		Irssi::print "  /set youtube_useragent SomeAgent/3.5";
		Irssi::print "";
		Irssi::print "Set the youtube timeout (in seconds) with:";
		Irssi::print "  /set youtube_timeout 3";
		Irssi::print "";
		Irssi::print "Toggle youtu.be shortlinks with:";
		Irssi::print "  /toggle youtube_shortlink";
		Irssi::print "";
		Irssi::print "Toggle automatically add HD to links with:";
		Irssi::print "  /toggle youtube_hdlink";
	}
}
# Settings
Irssi::settings_add_str('youtube', 'youtube_useragent', 'Firefox/3.5');
Irssi::settings_add_str('youtube', 'youtube_channels', '');
Irssi::settings_add_bool('youtube', 'youtube_hdlink' => 1);
Irssi::settings_add_bool('youtube', 'youtube_queries' => 1);
Irssi::settings_add_bool('youtube', 'youtube_shortlink' => 1);
Irssi::settings_add_int('youtube', 'youtube_timeout', 3);
Irssi::signal_add_first('send text', 'process_send_text');

# Show usage, maybe.
usage();

#####
# Version History
#####
## v1.3
# Many changes, same functionality.
#####
## v1.2
# Added youtube_timeout setting. Default 3 seconds.
#####
## v1.1
# Added cchecking for &fmt=18 on URLs.
## v1.0
# Initial Release
