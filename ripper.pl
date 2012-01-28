#!/usr/bin/perl -w

package ripper;

use feature ':5.12';
use strict;

#use Data::Dumper;
use File::Copy;
use File::Spec;
use File::Path;

my $config_file = $ENV{'RIPPER_CFG'} || "$ENV{'HOME'}/.ripper.ini";
my $config = {
    'wav_dir' => 'disk',
    'ripper' => '/usr/bin/cdparanoia',
    'ripper_opts' => '-v -w -B -d /dev/cdrom',
    'normalize' => '/usr/bin/normalize',
    'normalize_opts' => '-b --no-progress -a -11dbFS',
};
require 'common.pl';
$config = common::load_ini('ripper', $config, $config_file);

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

    my $cwd = `pwd`;
    chomp $cwd;

    my $wav_dir = $config->{'wav_dir'} || 'disk';
    my $dir = File::Spec->catdir($cwd, $wav_dir);
    unless (-e $dir) {
        mkpath($dir) or die "Failed to create $dir: $!";
    }

    if ($dirnum > 0) {
        $dir .= $dirnum;
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

    my $norm_file = File::Spec->catfile(
        $dir, $config->{'norm_file'} || 'norm_result'
    );
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
    my $cwd = `pwd`;
    chomp $cwd;

    my $wav_dir = $config->{'wav_dir'} || 'disk';
    my $dir = File::Spec->catdir($cwd, $wav_dir);

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
        my $disk_dir = $dir . $disknum;
        last unless -d $disk_dir;

        my @tracks = glob(
            File::Spec->catfile($disk_dir, 'track*.cdda.wav')
        );
        say "Disk $disknum: tracks=" . scalar(@tracks) . ", offset=$tracknum";

        foreach my $file (@tracks) {
            ++$tracknum;
            my $dest_file = $dir . sprintf("track%02d.cdda.wav", $tracknum);
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
Usage: perl ripper.pl [<num>|merge|norm]
USAGE
}

1;
