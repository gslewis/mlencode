#!/usr/bin/perl -w
package mlsync;

use strict;
use feature ':5.12';

if (@ARGV == 0) {
    usage_and_die();
}

use File::Basename;
use File::Spec;

# Include the script directory so we can load mlcommon.pl
push @INC, dirname($0);
my $config = init();

my $device = uc shift;
die "Invalid device $device\n" unless exists $config->{'devices'}->{$device};

# Local dir must end with '/' to ensure we sync its contents with the remote
# dir, not the dir itself.
my $local_dir = make_path($config->{'devices_dir'}, $device) . '/';
my $remote_dir = make_path($config->{'devices'}->{$device});

my @cmd = qw(rsync --verbose --recursive --update --size-only --delete);

# If the local and remote directories use different encodings, use the
# appropriate --iconv parameter for each direction.
my $sync_dirn = lc(shift || 'up');
if ($sync_dirn eq 'up') {
    #push @cmd, '--iconv=iso88591,utf8', $local_dir, $remote_dir;
    push @cmd, $local_dir, $remote_dir;
} elsif ($sync_dirn eq 'down') {
    #push @cmd, '--iconv=utf8,iso88591', $remote_dir, $local_dir;
    push @cmd, $remote_dir, $local_dir;
} else {
    usage_and_die();
}

my $cmd = join ' ', @cmd;
system $cmd;


sub make_path {
    die "Empty path\n" unless @_ > 0;

    unless (File::Spec->file_name_is_absolute($_[0])) {
        unshift @_, $ENV{'HOME'};
    }

    return File::Spec->catdir(@_);
}

sub init {
    my $config = shift || {};

    my $config_file = $ENV{'MLENCODE_INI'} || "$ENV{'HOME'}/.mlencode.ini";

    require 'mlcommon.pl';
    $config = mlcommon::load_ini('mlsync', $config, $config_file);

    die "Missing 'device_musiclib_dir' map.\n"
        unless defined $config->{'device_musiclib_dir'};

    die "Missing 'devices' list.\n" unless defined $config->{'devices'};

    # Map the device name to the location of its musiclib directory.  This is
    # usually just recreating the device_musiclib_dir hash but handles the
    # config validation.  The .mlencode.ini file may have either a single
    # 'device_musiclib_dir' or a directory for each device.
    my %device_map = map {
        my $dir = undef;
        if ('HASH' eq ref $config->{'device_musiclib_dir'}) {
            $dir = $config->{'device_musiclib_dir'}->{$_}
                    || die "Missing 'device_musiclib_dir' for $_\n";
        } else {
            $dir = $config->{'device_musiclib_dir'};
        }

        uc $_ => $dir;
    } split /,/, $config->{'devices'};

    $config->{'devices'} = \%device_map;

    return $config;
}

sub usage_and_die {
    say "Usage: perl mlsync.pl <device> up|down";
    exit;
}

1;
