use strict;
use Irssi;

use vars qw($VERSION %IRSSI);

$VERSION = "0.9a";
%IRSSI = (
	authors		=> "David O\'Rourke",
	contact		=> "???",
	name		=> "DCC Exploit KICKBAN",
	description	=> "KICKBAN anyone sending a DCC SEND to an entire channel, like most are doing with the dcc exploit for mIRC.",
	licence		=> "GNU General Public Licence",
	changed		=> "07.01.2004 19:59"
);

sub exploit_close {
	my ($server, $args, $nickname, $address, $target) = @_;
	my $chan;

	if ($target =~ /^\#/) {
		$chan = $target;
	}
	else {
		return;
	}

	# Stop the signal
	Irssi::signal_stop();

	# Don't kick ops that are doing it (was used during testing script)
	if $server->channel_find($chan)->nick_find($nickname)->{op} {
		return;
	}

	# Can't kickban them if we're not an op.
	my $chanrec = $server->channel_find($chan);
	if (!$chanrec->{chanop}) {
		return;
	}

	# Kickban.
	$server->command("KICKBAN $chan $nickname No Thanks");
	Irssi::print "Banned $nickname!$address on $chan";
}

Irssi::signal_add_first('ctcp msg dcc send', 'exploit_close');

###############
## ChangeLog ##
###############
# 01.07.2004: Jan 07 2004: 19:59
# Rewrote script to use 'ctcp msg dcc send' instead of 'dcc request'
# 12.11.2003: Dec 11 2003: 13:12
# Fixed closing the DCC
# 12.11.2003: Dec 11 2003: 03:25
# Added a line to reject the DCC offer
