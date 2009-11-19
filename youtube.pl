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
$VERSION = "1.1";
%IRSSI = (
	authors		=> "David O'Rourke",
	contact		=> "phyber @ #irssi",
	name		=> "youtube.pl",
	description	=> "Add the title of a video to any youtube links you paste.",
	license		=> "GPLv2",
	changed		=> "2009/11/19",
);

##
sub get_youtube_title {
	my ($url) = @_;

	# Get a user agent
	my $ua = LWP::UserAgent->new;
	# Set the UserAgent of the UserAgent
	my $agent = Irssi::settings_get_str('youtube_useragent');
	$ua->agent($agent." ");

	# OK, now go and get the page and let the magic happen
	my $response = $ua->get($url);
	if ($response->is_success) {
		my $p = HTML::TokeParser->new(\$response->content);
		if ($p->get_tag("title")) {
			my $title = $p->get_trimmed_text;
			$title =~ s/YouTube\s- //;
			return $title;
		}
		else {
			Irssi::print "Failed to get title for YouTube URL: $url";
			return undef;
		}
	}
	else {
		Irssi::print "Failed to fetch page for YouTube URL: $url";
		return undef;
	}
}

sub process_send_text {
	my ($msg, $server_rec, $witem) = @_;

	if ($msg and $witem != 0 and $witem->{type} eq "CHANNEL") {
		my $tag = $server_rec->{tag};
		my $channel = $witem->{name};
		my $valid_chan;
		# Check if we want to run in this tag and channel
		foreach my $tc (split / /, Irssi::settings_get_str('youtube_channels')) {
			my ($t, $c) = split /:/, $tc;
			if ((lc($t) eq lc($tag)) and (lc($c) eq lc($channel))) {
				$valid_chan = 1;
				last;
			}
		}
		if ($valid_chan) {
			my @words = split / /, $msg;
			my $count = 0;
			foreach my $s (@words) {
				if ($s =~ m/^(http(s?):\/\/)(www\.)?youtube\.com\/watch\?v=/) {
					my $title = get_youtube_title($s);
					if (defined $title) {
						# If we got the title, also check if we wanted to make it a HD link
						if (Irssi::settings_get_bool('youtube_hdlink')) {
							if (!($s =~ m/fmt=18/)) {
								$s = $s."&fmt=18";
							}
						}
						my $new_text = "$s ($title)";
						$words[$count] = $new_text;
					}
				}
				$count = $count + 1;
			}
			Irssi::signal_continue((join(' ', @words), $server_rec, $witem));
		}
	}
}

sub usage {
	# If we haven't got any channels set, print the usage.
	if (Irssi::settings_get_str('youtube_channels') eq '') {
		Irssi::print "youtube.pl v$VERSION";
		Irssi::print "Add channels to run in with:";
		Irssi::print "  /set youtube_channels tag:#channel";
		Irssi::print "The scripts useragent can be set with:";
		Irssi::print "  /set youtube_useragent SomeAgent/3.5";
	}
}
# Settings
Irssi::settings_add_str('youtube', 'youtube_useragent', 'Firefox/3.5');
Irssi::settings_add_str('youtube', 'youtube_channels', '');
Irssi::settings_add_bool('youtube', 'youtube_hdlink' => 1);
Irssi::signal_add_first('send text', 'process_send_text');

# Show usage, maybe.
usage();

#####
# Version History
#####
## v1.1
# Added cchecking for &fmt=18 on URLs.
## v1.0
# Initial Release
