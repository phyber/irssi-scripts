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

sub process_own_public {
	my ($server_rec, $msg, $target) = @_;
	# Now check each word and check if it's a youtube url
	# We only accept one url per input.
	if (lc($target) eq lc("#laserboy")) {
		my $url;
		# Build an aray from our input msg.
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

		Irssi::signal_continue(($server_rec, join(' ', @words), $target));
	}
}

# Settings
Irssi::settings_add_str('youtube', 'youtube_useragent', 'Firefox 3.5');
Irssi::signal_add_first('message own_public', 'process_own_public');
