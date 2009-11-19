use strict;
use warnings;
use Irssi;
use LWP::UserAgent;
use HTML::TokeParser;

# Setup a UserAgent
my $ua = LWP::UserAgent->new;
sub get_youtube_title {
	my ($url) = @_;

	# Set the UserAgent of the UserAgent
	my $agent = Irssi::settings_get_str('youtube_useragent');
	$ua->agent($agent." ");
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
					my $new_text = "$s ($title)";
					$words[$count] = $new_text;
				}
				$count = $count + 1;
			}
			Irssi::signal_continue((join(' ', @words), $server_rec, $witem));
		}
	}
}

# Settings
Irssi::settings_add_str('youtube', 'youtube_useragent', 'Firefox 3.5');
Irssi::settings_add_str('youtube', 'youtube_channels', '');
Irssi::signal_add_first('send text', 'process_send_text');
