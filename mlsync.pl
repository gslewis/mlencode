#!/usr/bin/perl -w
package mlsync;

use strict;
use feature ':5.12';

if (@ARGV == 0) {
    say "Usage: perl mlsync.pl <device> up|down";
    exit;
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
my $remote_dir = make_path($config->{'device_musiclib_dir'});

my @cmd = qw(rsync --verbose --recursive --update --size-only --delete);

my $sync_dirn = lc(shift || 'up');
if ($sync_dirn eq 'up') {
    push @cmd, $local_dir, $remote_dir;
} elsif ($sync_dirn eq 'down') {
    push @cmd, $remote_dir, $local_dir;
}

system @cmd;


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

    die "Missing 'device_musiclib_dir'\n"
        unless defined $config->{'device_musiclib_dir'};
    die "Missing 'devices'\n" unless defined $config->{'devices'};

    my %device_map = map { $_ => 1 } split /,/, $config->{'devices'};
    $config->{'devices'} = \%device_map;

    return $config;
}

1;
