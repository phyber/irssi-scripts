use strict;
use XML::Simple;
use LWP::UserAgent;
use Data::Dumper;
use POSIX;
use Irssi;
use vars qw($VERSION %IRSSI);

my $VERSION = '1.0';
my %IRSSI = (
	authors		=> "David O'Rourke",
	contact		=> "???",
	name		=> "sabstatus",
	description	=> "Show current queue info from SABnzbd on the irssi statusbars.",
	license		=> "GPLv2",
	changed		=> "2009-04-24",
);
my $pipe_tag;
my $status_timeout;
my $status_overall = "N/A";
my $status_downloads = "N/A";

sub sbar_refresh {
	Irssi::statusbar_items_redraw('sabstatus');
}

sub sbar_show {
	my ($item, $get_size_only) = @_;
	my $format = "{sb SAB: $status_overall}";
	$item->default_handler($get_size_only, $format, 0, 1);
}

sub pipe_input {
	my ($readh) = @_;
	my $text = <$readh>;
	close($readh);
	($status_overall, $status_downloads) = split /\n/, $text, 2;


	Irssi::input_remove($pipe_tag);
	$pipe_tag = -1;

	# Trigger a statusbar refresh after we get the data.
	Irssi::statusbar_items_redraw('sabstatus');
}

sub show_status {
	if ($status_overall) {
		Irssi::print "OVERALL..: $status_overall";
	}
	if ($status_downloads) {
		Irssi::print "DOWNLOADS..: $status_downloads";
	}
}

sub get_status {
	# grab the settings
	my $username	= Irssi::settings_get_str('sabstatus_username');
	my $password	= Irssi::settings_get_str('sabstatus_password');
	my $sabnzbd	= Irssi::settings_get_str('sabstatus_sabnzbd');
	my $apikey	= Irssi::settings_get_str('sabstatus_apikey');
	my $timeout	= Irssi::settings_get_int('sabstatus_timeout');
	# make the url
	my $saburl = sprintf "http://%s/sabnzbd/api?mode=qstatus&output=xml&apikey=%s&ma_username=%s&ma_password=%s", $sabnzbd, $apikey, $username, $password;
	# make the user agent, ready for the request
	my $ua = LWP::UserAgent->new;
	$ua->timeout($timeout);

	# need these for reading from the child
	my ($readh, $writeh);
	pipe ($readh, $writeh);
	# fork
	my $pid = fork();
	if (!defined $pid) {
		Irssi::print "Can't fork(), aborting.";
		close($readh);
		close($writeh);
		return;
	}

	if ($pid > 0) {
		# Irssi waiting for reply
		close($writeh);
		Irssi::pidwait_add($pid);
		$pipe_tag = Irssi::input_add(fileno($readh), INPUT_READ, \&pipe_input, $readh);
		return;
	}
	else {
		# OK, go and get it
		my $response = $ua->get($saburl);
		if ($response->is_success) {
			my $text = "";
			my $overall_format_str = Irssi::settings_get_str('sabstatus_overall_format');
			my $xml = XMLin($response->content);
			# Overall status
			my $timeleft	= $xml->{timeleft};
			my $speed	= $xml->{kbpersec};
			my $numjobs	= $xml->{noofslots};
			my $dlspace	= sprintf "%.2fGB", $xml->{diskspace1};
			my $compspace	= sprintf "%.2fGB", $xml->{diskspace2};
			my $paused	= $xml->{paused} eq "True" ? "paused" : "";
			my $mbdown	= $xml->{mb};
			my $mbleft	= $xml->{mbleft};
			# Replace bits of the format string with info we got above.
			$overall_format_str =~ s/%JOBS%/$numjobs/g;
			$overall_format_str =~ s/%KBPERSEC%/$speed/g;
			$overall_format_str =~ s/%PAUSED%/$paused/g;
			$overall_format_str =~ s/%MBLEFT%/$mbleft/g;
			$overall_format_str =~ s/%MB%/$mbdown/g;
			$overall_format_str =~ s/%TIMELEFT%/$timeleft/g;
			$overall_format_str =~ s/%DISKSPACE1%/$dlspace/g;
			$overall_format_str =~ s/%DISKSPACE2%/$compspace/g;

			#$text = sprintf "%d jobs in %s queue with %dMB and %ss left at %sKB/s.  Diskspace: %s/%s.\n", $numjobs, $paused, $mbleft, $timeleft, $speed, $dlspace, $compspace;
			$text = $overall_format_str ."\n";
			# Specific jobs
			foreach my $jobid (keys %{$xml->{jobs}->{job}}) {
				my $job = $xml->{jobs}->{job}->{$jobid};
				next if !$job;
				my $downloads_format_str = Irssi::settings_get_str('sabstatus_downloads_format');
				my $filename = $job->{filename};
				my $mb = $job->{mb};
				my $mbleft = $job->{mbleft};
				my $msgid = $job->{msgid};
				# String replacements
				$downloads_format_str =~ s/%JOBID%/$jobid/g;
				$downloads_format_str =~ s/%FILENAME%/$filename/g;
				$downloads_format_str =~ s/%MBLEFT%/$mbleft/g;
				$downloads_format_str =~ s/%MB%/$mb/g;
				$downloads_format_str =~ s/%MSGID%/$msgid/g;
			
				#Irssi::print "GOT: $jobid || $filename || $mb || $mbleft || $msgid";
				#$text .= "$jobid || $filename || $mb || $mbleft || $msgid //// ";
				$text .= $downloads_format_str . " ";
			}
			# Write the text out and exit the fork()
			print {$writeh} $text;
			close $writeh;
			POSIX::_exit(1);
		}
		else {
			print {$writeh} "Couldn't get SABnzbd status: ".$response->status_line;
			close $writeh;
			POSIX::_exit(1);
		}
	}
}

sub refresh_status {
	# grab the status from sab
	get_status();
}

## COMMANDS
Irssi::command_bind('sabstatus', 'show_status');
## STATUSBAR
Irssi::statusbar_item_register('sabstatus', '$0', 'sbar_show');
## SETTINGS
Irssi::settings_add_str('sabstatus', 'sabstatus_sabnzbd', 'localhost:8081');
Irssi::settings_add_str('sabstatus', 'sabstatus_apikey', 'ABCDEF');
Irssi::settings_add_str('sabstatus', 'sabstatus_username', 'username');
Irssi::settings_add_str('sabstatus', 'sabstatus_password', 'password');
Irssi::settings_add_str('sabstatus', 'sabstatus_overall_format', '%JOBS% in %PAUSED% queue with %MBLEFT% and %TIMELEFT% at %KBPERSEC%KB/s. Diskspace: %DISKSPACE1%/%DISKSPACE2%');
Irssi::settings_add_str('sabstatus', 'sabstatus_downloads_format', '%FILENAME - %MBLEFT%/%MB%');
Irssi::settings_add_int('sabstatus', 'sabstatus_interval', 30000);
Irssi::settings_add_int('sabstatus', 'sabstatus_timeout', 5);
## Initial status fetch and add timeout to refresh info
get_status();
$status_timeout = Irssi::timeout_add(Irssi::settings_get_int('sabstatus_interval'), 'refresh_status', undef);
