#!/usr/bin/perl -w
package addalbum;

=head1 NAME

addalbum.pl - Hard links album files in device directory.

=head1 SYNOPSIS

    # Get list of available devices
    perl addalbum.pl

    # Add single album to J3 device
    perl addalbum.pl j3 music/Peter_Gabriel/1986_So

=head1 DESCRIPTION

This script is used to manage a library for portable audio devices that can be
mounted as conventional file systems.  The main music library is located in,
say, the '~/music' directory.  Albums are created here using the ripper.pl and
encoder.pl scripts.

Separate libraries of albums are maintained for each device so the sync
scripts can be used to add and remove albums.  Instead of duplicating each
album in the device libraries, we use hard links to the main music library.

=head2 Configuration Options

The following configuration options are mandatory in the [addalbum] section of
the ~/.ripper.ini configuration file.

=over

=item devices_dir [addalbum]

The directory in which the device libraries are located.  If not an absolute
path is relative to the current directory.

Example: devices_dir = media/devices

=item devices [addalbum]

Comma-separated list of devices.  Each name corresponds to a sub-directory of
the 'devices_dir.

Example: devices = J3,I9

=back

=cut

use strict;
use feature ':5.12';
use File::Basename;
use File::Glob;
use File::Spec;
use Cwd;

# Add the script dir to @INC so we can load common.pl
push @INC, dirname($0);

my $config = {
    # no defaults
};
$config = init($config);

if (@ARGV == 0) {
    say "perl addalbum.pl <device> <album1> <album2> ...";
    say "Devices: " . join ', ', keys(%{$config->{'devices'}});
    exit;
}

my $device = uc shift;
die "Invalid device $device\n" unless exists $config->{'devices'}->{$device};

my $device_dir = File::Spec->catdir(
    $config->{'devices_dir'},
    $device
);

my $cwd = getcwd();
foreach my $album (@ARGV) {
    my $album_dir;

    if (File::Spec->file_name_is_absolute($album)) {
        $album_dir = $album;
    } else {
        $album_dir = File::Spec->catdir($cwd, $album);
    }

    unless (-d $album_dir) {
        say "No such album '$album'";
    } else {
        add_album($album_dir, $device_dir);
    }
}

sub add_album {
    my ($album_dir, $device_dir) = @_;

    my $album = basename($album_dir);

    # Test for standard album directory (contains a 'data' file).
    unless (-e File::Spec->catfile($album_dir, 'data')) {
        say "Album '$album' missing 'data' file";
        return;
    }

    # Get the artist name.
    my $artist = basename(dirname($album_dir));

    # Strip any leading 'The_' from the artist.
    my $artist_base = $artist;
    $artist_base =~ s/^The_//;
    unless ($artist_base =~ /^[A-Za-z0-9]/) {
        say "Invalid artist '$artist'";
        return;
    }

    # Get the sub-dir in the device repos that contains the artist.
    my $target_dir = File::Spec->catdir($device_dir,
                                        get_dest_dir($artist_base));
    unless (-d $target_dir) {
        say "Creating directory $target_dir";
        mkdir $target_dir;
    }

    # Get the artist directory in the device repos.
    my $artist_dir = File::Spec->catdir($target_dir, $artist);
    unless (-d $artist_dir) {
        say "Creating directory $artist_dir";
        mkdir $artist_dir;
    }

    # Get the album directory in the device repos.  Abort if the album exists.
    my $dest_dir = File::Spec->catdir($artist_dir, $album);
    if (-d $dest_dir) {
        say "Album '$album' destination already exists.  Skipping...";
        return;
    } else {
        say "Creating directory $dest_dir";
        mkdir $dest_dir;
    }

    # Hard link all audio files (plus cover.jpg if present) to the album
    # directory in the device repos.
    my @files = <$album_dir/[0-9]*.{ogg,flac,mp3} $album_dir/cover.jpg>;
    @files = sort @files;
    foreach my $file (@files) {
        my $filename = basename($file);
        my $dest = File::Spec->catfile($dest_dir, $filename);

        if (-e $file) {
            say "\t$filename";
            link $file, $dest;
        } else {
            say "\tMISS: $filename";
        }
    }
}

sub get_dest_dir {
    my $artist = shift;

    my $ch = lc substr($artist, 0, 1);
    if ($ch =~ /[0-9]/) {
        # List of first letters for each digit.
        my @n2c = ('z', 'o', 't', 't', 'f', 'f', 's', 's', 'e', 'n');
        $ch = $n2c[$ch];
    }

    return $ch;
}

sub init {
    my $config = shift || {};

    my $config_file = $ENV{'RIPPER_CFG'} || "$ENV{'HOME'}/.ripper.ini";

    require 'common.pl';
    $config = common::load_ini('addalbum', $config, $config_file);

    die "Missing 'devices_dir'\n" unless defined $config->{'devices_dir'};
    die "Missing 'devices'\n" unless defined $config->{'devices'};

    # Convert string list of devices to map.
    # TODO: mapped value should be the capacity of the device.
    my %device_map =  map { $_ => 1 } split /,/, $config->{'devices'};
    $config->{'devices'} = \%device_map;

    return $config;
}

1;
