##
# /toggle whitelist_notify [default ON]
# Print a message in the status window if someone not on the whitelist messages us
#
# /toggle whitelist_log_ignored_msgs [default ON]
# if this is on, ignored messages will be logged to ~/.irssi/whitelist.log
#
# /toggle whitelist_nicks_case_sensitive [default OFF]
# do we care which case nicknames are in?
#
# Thanks to Geert for help/suggestions on this script
#
# Karl "Sique" Siegemund's addition:
# Managing the whitelists with the /whitelist command:
#
# /whitelist add nick <list of nicks>
# puts new nicks into the whitelist_nicks list
#
# /whitelist add host <list of hosts>
# puts new hosts into the whitelist_hosts list
#
# /whitelist add chan[nel] <list of channels>
# puts new channels into the whitelist_channels list
#
# /whitelist add net[work] <list of chatnets/servers>
# puts new chatnets or irc servers into the whitelist_networks list
#
# /whitelist del nick <list of nicks>
# removes the nicks from whitelist_nicks
#
# /whitelist del host <list of hosts>
# removes the hosts from whitelist_hosts
#
# /whitelist del chan[nel] <list of channels>
# removes the channels from whitelist_channels
#
# /whitelist del net[work] <list of chatnets/servers>
# removes the chatnets or irc servers from whitelist_networks
#
# Instead of the 'del' modifier you can also use 'remove':
# /whitelist remove [...]
#
# /whitelist nick
# shows the current whitelist_nicks
#
# /whitelist host
# shows the current whitelist_hosts
#
# /whitelist chan[nel]
# shows the current whitelist_channels
#
# /whitelist net[work]
# shows the current whitelist_networks
#
# Additional feature for nicks, channels and hosts:
# You may use <nick>@<network>/<ircserver>, <host>@<network>/<ircserver>
# and <channel>@<network>/<ircserver> to restrict the whitelisting to the
# specified network or ircserver.
#
# The new commands are quite verbose. They are so for a reason: The commands
# should be easy to remember and self explaining. If someone wants shorter
# commands, feel free to use 'alias'.
##
# /whitelist show
# shows you all of the whitelisted entries.

use strict;
use Irssi;
use Irssi::Irc;
use IO::File;

use vars qw($VERSION %IRSSI);
$VERSION = "1.3";
%IRSSI = (
    authors     => "David O\'Rourke, Karl Siegemund",
    contact     => "phyber \[at\] #irssi, q \[at\] spuk.de",
    name        => "whitelist",
    description => "Whitelist specific nicks or hosts and ignore messages from anyone else.",
    licence     => "GPLv2",
    changed     => "20/03/2018 17:11 GMT"
);

# Location of the settings file
my $settings_file = Irssi::get_irssi_dir.'/whitelist.conf';

# This hash stores our various whitelists.
my %whitelisted;

# A mapping to convert simple regexp (* and ?) into Perl regexp
my %htr = ( );
foreach my $i (0..255) {
    my $ch = chr($i);
    $htr{$ch} = "\Q$ch\E";
}
$htr{'?'} = '.';
$htr{'*'} = '.*';

# A list of settings we can use and change
my %types = (
    'nick'    => 'nicks',
    'host'    => 'hosts',
    'chan'    => 'channels',
    'channel' => 'channels',
    'net'     => 'networks',
    'network' => 'networks',
);

# Turns a given hostmask into a regexp.
sub host_to_regexp {
    my ($mask) = @_;

    $mask = lc_host($mask);
    $mask =~ s/(.)/$htr{$1}/g;

    return $mask;
}

# Lowercases the host portion of a user!ident@host string
sub lc_host {
    my ($host) = @_;

    $host =~ s/(.+)\@(.+)/sprintf("%s@%s", $1, lc($2));/eg;

    return $host;
}

# Show the current config
sub print_config {
    foreach my $listtype (keys %whitelisted) {
        my $str = join ' ', @{$whitelisted{$listtype}};

        Irssi::print "Whitelisted $listtype: $str";
    }
}

# Read in the whitelist.conf
sub read_config {
    # nicks, hosts, channels, networks
    my $f = IO::File->new($settings_file, 'r');
    if (!defined $f) {
        # No config file, it's probably a first run.
        return;
    }

    while (<$f>) {
        chomp;
        my ($listtype, @list) = split / /, $_;

        # Make sure there is no duplicate weirdness
        @{$whitelisted{$listtype}} = unique(@list); #map { $_ } @list;
    }
    $f = undef;
}

# Write out the whitelist.conf
sub write_config {
    my $f = IO::File->new($settings_file, 'w');
    die "Couldn't open $settings_file for writing" if (!defined $f);

    foreach my $listtype (keys %whitelisted) {
        # Avoid writing blank lines into the config
        next if not length $listtype;

        # Make sure we arn't writing duplicates
        @{$whitelisted{$listtype}} = unique(@{$whitelisted{$listtype}});

        # Now write that list to the config.
        my $str = join ' ', @{$whitelisted{$listtype}};
        print {$f} "$listtype $str\n";
    }

    $f = undef;
}

# Return a unique array.
sub unique {
    my %seen;
    return grep { !$seen{$_}++ } @_;
}

# Logs a message in the whitelist log. Entries are prefixed with the
# localtime() followed by ": ", and ending with a newline.
sub log_msg {
    my ($logentry) = @_;

    my $logfile = Irssi::get_irssi_dir.'/whitelist.log';
    my $f = IO::File->new($logfile, '>>');
    return if (!defined $f);

    print {$f} localtime().": $logentry\n";
    $f = undef;
}

# Check if a network is whitelisted
sub network_whitelisted {
    my ($server, $tag, $nick) = @_;

    my $network_chan_only = Irssi::settings_get_bool('whitelist_network_channel_only');

    foreach my $netentry (@{$whitelisted{'networks'}}) {
        # Copy it so we don't modify the array
        my $network = $netentry;

        # Change it to lower case
        $network = lc($network);

        # Kludge. Sometimes you get superfluous '', you have to ignore
        next if ($network eq '');

        # Rewrite simplified regexp (* and ?) to Perl regexp
        $network =~ s/(.)/$htr{$1}/g;

        # Either the server tag matches
        return 1 if ($tag =~ /$network/);

        # Or its address
        return 1 if ($server->{address} =~ /$network/);

        # Finally, check if the nick exists in any channels at all, if we have
        # 'whitelist_network_channel_only' enabled.
        if ($network_chan_only) {
            foreach my $channel ($server->channels()) {
                return 1 if defined $channel->nick_find($nick);
            }
        }
    }

    # Network isn't whitelisted
    return 0;
}

# Check if the nick is whitelisted
sub nick_whitelisted {
    my ($server, $tag, $nick) = @_;

    my $casesensitive = Irssi::settings_get_bool('whitelist_nicks_case_sensitive');

    foreach my $whitenickentry (@{$whitelisted{'nicks'}}) {
        # copy it so we don't modify the array
        my $whitenick = $whitenickentry;

        # Lower case everything if we are case insensitive.
        if (!$casesensitive) {
            $nick      = lc($nick);
            $whitenick = lc($whitenick);
        }

        # Simple check first: Is the nick itself whitelisted?
        return 1 if ($nick eq $whitenick);

        # Second check: We have to look if the nick was localized to a network
        # or irc server. So we have to look at <nick>@<network> too.
        ($whitenick, my $network) = split /@/, $whitenick, 2;

        # Ignore nicks without @<network>
        next if !defined $network;

        # Convert simple regexp to Perl regexp
        $network =~ s/(.)/$htr{$1}/g;

        # If the nick matches...
        if ($nick eq $whitenick) {
            # ...allow if the server tag is right...
            return 1 if ($tag =~ /$network/);

            # ...or the server address matches
            return 1 if ($server->{address} =~ /$network/);
        }
    }

    # Nick isn't whitelisted
    return 0;
}

# Check if the host is whitelisted
sub host_whitelisted {
    my ($server, $tag, $hostmask) = @_;

    foreach my $whitehostentry (@{$whitelisted{'hosts'}}) {
        # copy it so we don't modify the array
        my $whitehost = $whitehostentry;

        # Kludge, sometimes you get ''
        next if ($whitehost eq '');

        # First reconvert simple regexp to Perl regexp
        $whitehost = host_to_regexp($whitehost);

        # Allow if the hostmask matches
        return 1 if ($hostmask =~ /$whitehost/);

        # Check if hostmask is localized to a network
        (my $whitename, $whitehost, my $network) = split /@/, $whitehost, 3;

        # Ignore hostmasks without attached network
        next if !defined $network;

        # We don't need to convert the network address again
        # $network =~ s/(.)/$htr{$1}/g;
        # But we have to reassemble the hostmask
        $whitehost = "$whitename\@$whitehost";

        # If the hostmask matches...
        if ($hostmask eq $whitehost) {
            # ...allow if the server tag is ok...
            return 1 if ($tag =~ /$network/);

            # ... or the server address
            return 1 if ($server->{address} =~ /$network/);
        }
    }

    # Host isn't whitelisted
    return 0;
}

# Check if channel is whitelisted
sub channel_whitelisted {
    my ($server, $tag, $nick) = @_;

    foreach my $channel (@{$whitelisted{'channels'}}) {
        # Check if we are on the specified channel
        my $chan = $server->channel_find($channel);

        # If yes...
        if (defined $chan) {
            # Check if the nick in question is also on that channel
            my $chk = $chan->nick_find($nick);

            # Allow the message
            return 1 if defined $chk;
        }

        # Check if we are talking about a localized channel
        ($chan, my $network) = split /@/, $_, 2;

        # Ignore not localized channels
        next if !defined $network;

        # Convert simple regexp to Perl regexp
        $network =~ s/(.)/$htr{$1}/g;

        # Ignore channels from a differently tagged server or from a different
        # address
        next if (!($tag =~ /$network/ || $server->{address} =~ /$network/));

        # Check if we are on the channel
        $chan = $server->channel_find($chan);

        # Ignore if not
        next unless defined $chan;

        # Check if $nick is on that channel too
        my $chk = $chan->nick_find($nick);

        # Allow if yes
        return 1 if defined $chk;
    }

    # Channel isn't whitelisted
    return 0;
}

# This one gets called from IRSSI if we get a private message (PRIVMSG)
sub whitelist_check {
    my ($server, $msg, $nick, $address) = @_;

    # $tag is used by all whitelist checks.
    my $tag = $server->{chatnet};
    $tag    = $server->{tag} unless defined $tag;
    $tag    = lc($tag);

    # Handle servers first, because they are the most significant,
    # Nicks, Channels and Hostmasks are always local to a network
    return if network_whitelisted $server, $tag, $nick;

    # Nicks are the easiest to handle with the least computational effort.
    # So do them before hosts and networks.
    return if nick_whitelisted $server, $tag, $nick;


    # Hostmasks are somewhat more sophisticated, because they allow wildcards
    my $hostmask = "$nick!$address";
    return if host_whitelisted $server, $tag, $hostmask;

    # Channels require some interaction with the server, so we do them last,
    # hoping that some ACCEPT cases are already done, thus saving computation
    # time and effort
    return if channel_whitelisted $server, $tag, $nick;

    # Do we want a notice about this message attempt?
    my $warning = Irssi::settings_get_bool('whitelist_notify');
    if ($warning) {
        Irssi::print "[$tag] $nick [$address] attempted to send private message.";
    }

    # Do we want to make a log entry for it?
    my $logging = Irssi::settings_get_bool('whitelist_log_ignored_msgs');
    if ($logging) {
        my $logentry = "[$tag] $nick [$address]: $msg";

        log_msg $logentry;
    }

    # Stop if the message isn't from a whitelisted address
    Irssi::signal_stop();
    return;
}

# Print out usage info
sub usage {
    Irssi::print "Usage: whitelist (add|del|remove) (nick|host|chan[nel]|net[work]) <list>";
    Irssi::print "       whitelist (nick|host|chan[nel]|net[work])";
    Irssi::print "       whitelist show";
}

# This is bound to the /whitelist command
sub whitelist_cmd {
    my ($args, $server, $winit) = @_;
    my ($cmd, $type, $rest) = split /\s+/, $args, 3;

    # What type of settings we want to change?
    my $listtype = $types{$type};

    # If we didn't get a syntactically correct command, put out an error
    if (!defined $listtype && defined $type) {
        usage();
        return;
    }

    # What are we doing?
    if ($cmd eq 'add') {
        # Split $rest into a list.
        my @list = split /\s+/, $rest;

        # Add the entries to the whitelist and then make sure it's unique
        foreach my $entry (@list) {
            push @{$whitelisted{$listtype}}, $entry;
        }

        # Make sure that the array only contains unique entries
        @{$whitelisted{$listtype}} = unique(@{$whitelisted{$listtype}})
    }
    elsif ($cmd eq 'del' || $cmd eq 'remove') {
        # Escape all letters to protect the Perl Regexp special characters
        $rest =~ s/(.)/$htr{$1}/g;

        # Make a list of things we want removing.
        my @list = split /\s+/, $rest;

        # Use grep to remove the list of things we don't want anymore.
        foreach my $removal (@list) {
            @{$whitelisted{$listtype}} = grep {!/^$removal$/} @{$whitelisted{$listtype}};
        }
    }
    elsif ($cmd eq 'show') {
        # Just show the current config and return
        print_config();
        return;
    }
    elsif (!defined $type) {
        # Look if we just want to see the current values
        $listtype = $types{$cmd};

        if (defined $listtype) {
            # Print them
            Irssi::print "Whitelist ${cmd}s: ".join ' ', @{$whitelisted{$listtype}};
        }
        else {
            # Or give error message
            usage();
        }
        return;
    }
    else {
        # If we felt through until here, something went wrong
        usage();
        return;
    }

    # Display the changed value and store it in the settings
    Irssi::print "Whitelist ${type}s: ".join ' ', @{$whitelisted{$listtype}};

    # Save the new settings
    write_config();
    return;
}

# Boolean configuration
Irssi::settings_add_bool('whitelist', 'whitelist_log_ignored_msgs' => 1);
Irssi::settings_add_bool('whitelist', 'whitelist_network_channel_only' => 0);
Irssi::settings_add_bool('whitelist', 'whitelist_nicks_case_sensitive' => 0);
Irssi::settings_add_bool('whitelist', 'whitelist_notify' => 1);

# Signals we need
Irssi::signal_add_first('message private', \&whitelist_check);

# The /whitelist command
Irssi::command_bind('whitelist', \&whitelist_cmd);

# Read the config
\&read_config();

#########################
####### Changelog #######
### 1.3: David O'Rourke
# - Fix a small issue with writing a blank line to the settings file.
# - Convert script from tabs to spaces.
# - Fix up some indentation and space code out a bit better for more
#   readability.
# - Attempt to make changelog slightly more readable
# - Remove the '/whitelist old2new' and '/whitelist upgrade' functions. These
#   are probably over a decade old now, and shouldn't be needed any longer.
# - Remove '/set' settings, 'whitelist_channels', 'whitelist_hosts',
#   'whitelist_networks', and 'whitelist_nicks'. These should have been
#   upgraded long ago and were no longer used.
# - Move logging into its own function.
# - Break out each type of whitelist check into its own function.
### 1.2: David O'Rourke
# - Added a new toggle: whitelist_network_channel_only
#   If enabled, this new option means that if you whitelist a network, that
#   only people in one of your channels on that network will be able to PM you.
#   If it's disabled (the default), the old behaviour happens, anyone on that
#   network (in one of your channels or not) will be able to PM you.
### 1.1: David O'Rourke
# - Made a small function named unique() which checks that entries in an array
#   are unique.
# - Modified various parts of the script to use the new unique() function.
# - Fixed the check function so that it doesn't modify the array it's checking.
#   (It was lc()ing things).
# - Removed some old commented out code.  Added a few comments to various
#   things.
### 1.0: David O'Rourke
# - Changed how whitelists are stored.  We no longer use the settings_*_str for
#   them.
# - We now store them in a hash and write/read a config file.
# - Added '/whitelist old2new' function, for converting to the new style list.
# - Added '/whitelist show' for showing everything that's been whitelisted.
### 0.9g: David O'Rourke
# - Cleanups.
### 0.9f: David O'Rourke
# - Cleanups.
### 0.9e: David O'Rourke
# - Changed print -> Irssi::print
# - Fixed '' in $whitehost
#########################
# 0.9d: David O'Rourke
# - General cleanup of script.
# - Removed pointless function timestamp()
# - Removed pointless global variables $tstamp, $whitenick, $whitehost
# - Created whitelist logging directory in ~/.irssi with option to rotate log
#   daily.
# - Fixed comparison of whitelist_networks to $tag.  $tag was being lowercased,
#   whitelist_networks was not.
####
