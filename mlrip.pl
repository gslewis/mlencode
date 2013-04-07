#!/usr/bin/perl -w
package mlrip;

=head1 NAME

mlrip.pl - Rips and normalizes single- or multi-disk albums.

=head1 SYNOPSIS

    # Rip and normalize a single disk album
    perl mlrip.pl

    # Rip the first disk of an album
    perl mlrip.pl 1
    # ... swap disks and rip disk two.
    perl mlrip.pl 2
    # Merge the two disks into a single set of tracks and normalize
    perl mlrip.pl merge

    # Normalise a set of WAVs (created by flac2wav.pl)
    perl mlrip.pl norm

=head1 DESCRIPTION

Produces a set of normalized WAV files in the 'wav_dir' directory ready for
use by the encoder.pl script.

The main feature of this script is to simplify the process of ripping
multi-disk CDs.  The steps are: 1). rip each disk into separate directories,
2). rename tracks in the 2nd, 3rd, etc disks to produce a single set of
consecutive tracks, 3). normalize the entire batch of tracks.  While it is
still necessary to rip each disk separately, the remaining steps
(renaming and normalizing) are performed together.

=head2 Configuration Options

The script is configured by the ~/.mlencode.ini configuration file (simple
'ini' format).  Global options (preceding an [section]s) are shared by other
scripts.  The mlrip.pl options are in the [mlrip] section.

=over

=item wav_dir (global)

The directory in which the ripped disks are located.  If ripping a single
disk, the WAV files are located in this directory.  If ripping a multi-disk,
each disk is a sub-directory of this directory, and the WAVs are moved to this
directory when merging.  Default: disk

=item norm_file (global)

The name of the file in the 'wav_dir' that contains the normalization level
for the batch of WAVs.  Default: norm_result

=item ripper [mlrip]

Command used for ripping.

Default: /usr/bin/cdparanoia

=item ripper_opts [mlrip]

Options passed to the ripper command.

Default: -v -w -B -d /dev/cdrom

=item normalize [mlrip]

Command used for normalizing.

Default: /usr/bin/normalize

=item normalize_opts [mlrip]

Options passed to the normalize command.

Default: -b --no-progress -a -11dbFS

=back

=cut

use 5.012;
use strict;
use File::Copy;
use File::Spec;
use File::Path;
use Cwd;

my $config_file = $ENV{'MLENCODE_INI'} || "$ENV{'HOME'}/.mlencode.ini";
my $config = {
    'wav_dir' => 'disk',
    'norm_file' => 'norm_result',
    'ripper' => '/usr/bin/cdparanoia',
    'ripper_opts' => '-v -w -B -d /dev/cdrom',
    'normalize' => '/usr/bin/normalize',
    'normalize_opts' => '-b --no-progress -a -11dbFS',
};
require 'mlcommon.pl';
$config = mlcommon::load_ini('mlrip', $config, $config_file);

if (@ARGV == 0) {
    # single-disk norm
    norm(rip());
} elsif ($ARGV[0] eq 'norm') {
    norm();
} elsif ($ARGV[0] eq 'merge') {
    # multi-norm complete
    norm(merge());
} elsif ($ARGV[0] =~ /^(\d+)$/) {
    # multi-norm rip
    rip($1);
} else {
    usage();
}

sub rip {
    my $dirnum = shift || 0;

    my $cwd = getcwd();

    my $wav_dir = $config->{'wav_dir'} || 'disk';
    my $dir = File::Spec->catdir($cwd, $wav_dir);
    unless (-e $dir) {
        mkpath($dir) or die "Failed to create $dir: $!";
    }

    if ($dirnum > 0) {
        $dir = File::Spec->catdir($dir, $dirnum);
        if (-e $dir) {
            die "multi-norm: directory exists: $dir\n";
        } else {
            mkpath($dir) or die "multi-norm: failed to create $dir\n";
        }
    }

    chdir $dir;
    say "Ripping in $dir";

    my $cmd = $config->{'ripper'} . ' ' . $config->{'ripper_opts'};
    system $cmd;

    if ($?) {
        rmdir $dir if $dirnum;
        die "multi-norm: failed to rip disk"
                . ($dirnum ? " $dirnum" : '') . "\n";
    }

    # Discard any cdparanoia track00 which is empty and would break the merge
    # process.
    if (-e 'track00.cdda.wav') {
        unlink 'track00.cdda.wav';
    }

    chdir $cwd;

    return $dir;
}

sub norm {
    my $dir = shift || $config->{'wav_dir'} || 'disk';

    my $norm_file = File::Spec->catfile($dir, $config->{'norm_file'});
    unlink $norm_file;

    my $wav_path = File::Spec->catfile($dir, '*.wav');
    my $wav_count = () = glob($wav_path);
    if ($wav_count == 0) {
        die "No wavs to normalize in $dir\n";
    }

    say "Normalizing $wav_count tracks.";

    my $cmd = $config->{'normalize'}
            . ' ' . $config->{'normalize_opts'}
            . ' ' . $wav_path;

    local $_ = `$cmd 2>&1`;

    my $adjustment = undef;
    if (/Applying adjustment of (.*)\.\.\./m) {
        $adjustment = $1;
    } elsif (/Files are already normalized/m) {
        $adjustment = 'NONE';
    }

    `echo $adjustment > $norm_file`;

    say "normalize: adjustment $adjustment";
}

sub merge {
    my $wav_dir = $config->{'wav_dir'} || 'disk';
    my $dir = File::Spec->catdir(getcwd(), $wav_dir);

    # TODO make configurable -- only works for cdparanoia
    my $track_count = () = glob(
        File::Spec->catfile($dir, 'track*.cdda.wav')
    );
    if ($track_count > 0) {
        die "Tracks exist in merge directory.\n";
    }

    say "Merging tracks...";

    my $disknum = 1;
    my $tracknum = 0;
    while (1) {
        my $disk_dir = File::Spec->catdir($dir, $disknum);
        last unless -d $disk_dir;

        my @tracks = glob(
            File::Spec->catfile($disk_dir, 'track*.cdda.wav')
        );
        say "Disk $disknum: tracks=" . scalar(@tracks) . ", offset=$tracknum";

        foreach my $file (@tracks) {
            ++$tracknum;
            my $dest_file = File::Spec->catfile(
                $dir, sprintf("track%02d.cdda.wav", $tracknum)
            );
            move($file, $dest_file);
        }

        rmdir $disk_dir or die "Failed to delete $disk_dir: $!";

        ++$disknum;
    }

    if ($tracknum == 0) {
        die "No disks to merge\n";
    }

    return $dir;
}

sub usage {
    say <<USAGE
Usage: perl mlrip.pl [<num>|merge|norm]
USAGE
}

1;
