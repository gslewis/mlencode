#!/usr/bin/perl -w
package mlencode;

=head1 NAME

mlencode.pl - Encodes WAV files to ogg, mp3 or flac.

=head1 SYNOPSIS

    # Encode using defaults from ~/.mlencode.ini and data file 'data'
    perl mlencode.pl

    # Encode to given format, album data file 'data'
    perl mlencode.pl ogg
    perl mlencode.pl mp3
    perl mlencode.pl flac

    # Encode to ogg using album data file 'data.album'
    perl mlencode.pl ogg data.album

=head1 DESCRIPTION

Used in conjunction with ripper.pl, encodes the album of normalized WAV files
'wav_dir' to the selected format.  Album data is defined in the album data
file.  The encoded audio files are created in the ARTIST/YEAR_ALBUM directory
in the 'encode_output_dir'.  Configured by the ~/.mlencode.ini configuration
file.

Sets the standard tags (artist, album, year, track, tracknumber) plus an
'encoded on' comment and, if possible, a 'normalization' comment detailing the
normalization adjustment that has been applied to the track.

Uses oggenc for ogg, lame for mp3 and flac for flac.

=head2 Album Data File

By default album data is read from the 'data' file in the current directory.
An alternate data file can be specified on the command line as the 2nd
argument -- requires that the output audio format is specified.

The format of the data file is:

    BAND=Peter Gabriel
    ALBUM=So
    YEAR=1986
    Red Rain
    Sledgehammer
    Don't Give Up
    ...

Lines starting with '#' are comments.  Blank lines and comments are ignored.

It is possible to include the artist and album name in the track description.
Use '%%' to separate the album title from the track and use '@@' to separate
the artist from the track:

    # A 'best of' album for a single artist: album%%track
    BAND=Tom Petty & The Heartbreakers
    ALBUM=Greatest Hits
    YEAR=1993
    Tom Petty & The Heartbreakers%%Breakdown
    Damn The Torpedoes%%Refugee
    Full Moon Fever%%Free Fallin'
    ...

    # A 'various artists' album: artist@@track
    BAND=Various
    ALBUM=Heavy Metal
    YEAR=1981
    Sammy Hagar@@Heavy Metal
    Blue öyster Cult@@Veteran Of The Psychic Wars
    Cheap Trick@@Reach Out
    ...

If you want to specify artist and album in the track the pattern is
'artist@@album%%track'.

=head2 Configuration Options

The script is configured via the ~/.mlencode.ini configuration file.  Uses the
standard 'ini' file format.  Global settings are shared with other scripts,
encoder-specific settings are in the [mlencode] section. The following options
can be set:

=over

=item wav_dir (global)

The directory in which the normalized WAV files are located, as well as the
'norm_file' file (see ripper.pl).  Default: disk

=item norm_file (global)

The name of the file in the 'wav_dir' that contains the normalization level
for the batch of WAVs.  Default: norm_result

=item encode_output_dir [mlencode]

The directory to which the encoded files are written.  If not absolute, the
path is relative to the user's home directory.  Default: music

=item wav_type [mlencode]

The filename format of the WAV files.  May be either 'cdparanoia' or
'cdda2wav'.  If not specified, the WAV type is detected by examining the
contents of the 'wav_dir'.

=item wav_delete [mlencode]

If set to one of the supported audio formats (ogg, mp3 or flac) then after a
WAV file is encoded to this format it is deleted.

=item author [mlencode]

Optional string value used to prefix the 'encoded on' comment.  By default the
author is 'username@hostname'.

=item ogg_options, mp3_options, flac_options [mlencode]

The command-line parameters passed to the ogg (oggenc), mp3 (lame) and flac
(flac) encoders.  Do not include comment options.

=back

=cut

use 5.012;
use strict;
use File::Spec;
use File::Path;

require 'mlcommon.pl';

my @FORMATS = ('ogg', 'mp3', 'flac');

my $ENCODERS = {
    ogg => \&encode_ogg,
    mp3 => \&encode_mp3,
    flac => \&encode_flac,
};

my $WAV_TYPES = {
    cdparanoia => {
        prefix => "track",
        suffix => ".cdda.wav",
    },
    cdda2wav => {
        prefix => "audio_",
        suffix => ".wav",
    },
};


# Process command-line args.

my ($format, $data_file) = @ARGV;

$format = lc ($format || 'ogg');
die "Unknown format '$format'\n" unless grep { /^$format$/ } @FORMATS;

$data_file = $data_file || 'data';
die "Missing album data file '$data_file'\n" unless -e $data_file;


# Load config.

my $config = {
    'encode_output_dir' => 'music',
    'norm_file' => 'norm_result',
    'wav_dir' => 'disk',
    'wav_delete' => '',
};
$config = init($config);


my $album_data = mlcommon::get_album_data($data_file);
my $album_dir = get_album_dir($album_data);
my $wav_type = detect_batch();

my $start_time = time;

mlencode::encoder($format, $wav_type, $album_dir, $album_data);

my $sec = time - $start_time;
my $ftime = sprintf("%d:%02d:%02d", $sec/3600, ($sec/60)%60, $sec%60);
say "\n\nTotal encoding time: $ftime";


# Functions

sub encoder {
    my ($format, $wav_type, $album_dir, $album_data) = @_;

    if (-d $album_dir) {
        die "Album directory already exists: $album_dir\n";
    }

    mkpath($album_dir) or die "Failed to create $album_dir: $!";
    say "Created $album_dir";

    my $wav_dir = $config->{'wav_dir'} || 'disk';
    my $wav_prefix = $WAV_TYPES->{$wav_type}->{'prefix'};
    my $wav_suffix = $WAV_TYPES->{$wav_type}->{'suffix'};

    # Settings used for command-line args by the encoders.
    my $settings = {
        'norm_level' => $config->{'norm_level'},
        'encoded_on' => $config->{'encoded_on'},
        'year' => $album_data->{'year'},
    };

    my $track_count = 0;
    foreach (@{$album_data->{'tracks'}}) {
        ++$track_count;

        my $artist = undef;
        my $album = undef;
        my $track = undef;

        # Can specify per-track artist and album using the '@@' and '%%'
        # separators:
        #
        #   track
        #   artist@@track
        #   album%%track
        #   artist@@album%%track

        if (/^(.+)@@(.*)%%(.*)$/) {
            $artist = $1;
            $album = $2;
            $track = $3;
        } elsif (/^(.+)@@(.+)$/) {
            $artist = $1;
            $track = $2;
        } elsif (/^(.+)%%(.+)$/) {
            $album = $1;
            $track = $2;
        } else {
            $track = $_;
        }

        # Track can be called '0' which is false, so test length.
        unless (length $track) {
            die "Failed to determine title for track $track_count\n";
        }

        $settings->{'index'} = $track_count;
        $settings->{'artist'} = $artist || $album_data->{'artist'};
        $settings->{'album'} = $album || $album_data->{'album'};
        $settings->{'track'} = $track;

        my $enc_file = sprintf("%02d_%s.%s",
                            $track_count, sanitize($track), $format);
        my $outfile = File::Spec->catfile(($album_dir, $enc_file));


        # WAV file can be missing.  Use this if we only want to encode some of
        # the tracks.  Delete the WAV and place a bogus track entry in the
        # 'data' file so that the required WAVs and their track entries still
        # line up.

        my $wav_file = sprintf("%s%02d%s",
                            $wav_prefix, $track_count, $wav_suffix);
        my $infile = File::Spec->catfile($wav_dir, $wav_file);
        unless ($infile) {
            say "Skipping $wav_file";
            next;
        }

        my @cmd = $ENCODERS->{$format}($infile, $outfile, $settings);
        system @cmd;

        if ($config->{'wav_delete'} eq $format) {
            unlink $infile or die "Failed to delete $infile: $!";
        }
    }

    system('cp', $data_file, $album_dir);

    # If delete source for this format, delete the norm_result file as well.
    if ($config->{'wav_delete'} eq $format) {
        unlink File::Spec->catfile(
            $wav_dir,
            $config->{'norm_file'}
        );
    }
}

sub encode_ogg {
    my ($infile, $outfile, $settings) = @_;

    my @cmd = qw(oggenc);

    if (defined $config->{'ogg_options'}) {
        push @cmd, split(/\s+/, $config->{'ogg_options'});
    }

    push @cmd, ('-a', $settings->{'artist'});
    push @cmd, ('-l', $settings->{'album'});
    push @cmd, ('-t', $settings->{'track'});
    push @cmd, ('-d', $settings->{'year'});
    push @cmd, ('-N', $settings->{'index'});
    push @cmd, ('-c', 'ENCODED_ON=' . $settings->{'encoded_on'});

    if (defined $settings->{'norm_level'}) {
        push @cmd, ('-c', 'NORMALISATION=' . $settings->{'norm_level'});
    }

    push @cmd, ('-o', $outfile);
    push @cmd, $infile;

    return @cmd;
}

sub encode_mp3 {
    my ($infile, $outfile, $settings) = @_;

    my @cmd = qw(lame);

    if (defined $config->{'mp3_options'}) {
        push @cmd, split(/\s+/, $config->{'mp3_options'});
    }

    push @cmd, ('--ta', $settings->{'artist'});
    push @cmd, ('--tl', $settings->{'album'});
    push @cmd, ('--tt', $settings->{'track'});
    push @cmd, ('--ty', $settings->{'year'});
    push @cmd, ('--tn', $settings->{'index'});
    push @cmd, ('--tc', 'ENCODED_ON=' . $settings->{'encoded_on'});

    push @cmd, ($infile, $outfile);

    return @cmd;
}

sub encode_flac {
    my ($infile, $outfile, $settings) = @_;

    my @cmd = qw(flac);

    if (defined $config->{'flac_options'}) {
        push @cmd, split(/\s+/, $config->{'flac_options'});
    }

    push @cmd, ('-T', "artist=" . $settings->{'artist'});
    push @cmd, ('-T', "album=" . $settings->{'album'});
    push @cmd, ('-T', "title=" . $settings->{'track'});
    push @cmd, ('-T', "date=" . $settings->{'year'});
    push @cmd, ('-T', "tracknumber=" . $settings->{'index'});
    push @cmd, ('-T', 'ENCODED_ON=' . $settings->{'encoded_on'});

    if (defined $settings->{'norm_level'}) {
        push @cmd, ('-T', 'NORMALISATION=' . $settings->{'norm_level'});
    }

    push @cmd, ('-o', $outfile);
    push @cmd, $infile;

    return @cmd;
}

sub get_album_dir {
    my $album_data = shift;

    my @artist_dirs = (
        $config->{'encode_output_dir'},
        sanitize($album_data->{'artist'})
    );

    # If the config encode_output_dir value is not absolute, assume it is
    # relative to the HOME directory.
    unless (File::Spec->file_name_is_absolute($config->{'encode_output_dir'})) {
        unshift @artist_dirs, $ENV{'HOME'};
    }

    # If not ogg format, append .$format to dir name.
    my $dir_suffix = $format eq 'ogg' ? '' : '.' . $format;

    my $artist_dir = File::Spec->catdir(@artist_dirs);

    # Album directory: YEAR_ALBUM.SUFFIX
    my $album_dir = File::Spec->catdir(
        (
            $artist_dir, 
            sprintf("%d_%s%s",
                $album_data->{'year'},
                sanitize($album_data->{'album'}),
                $dir_suffix)
        )
    );

    return $album_dir;
}

sub detect_batch {
    my $wav_dir = $config->{'wav_dir'} || 'disk';

    die "Missing wav directory: $wav_dir\n" unless -d $wav_dir;

    # If wav type is set in the config, use it and don't detect.
    my $wav_type = $config->{'wav_type'};
    if ($wav_type) {
        die "Unsupport wav type: $wav_type\n"
            unless grep { /^$wav_type$/ } keys %$WAV_TYPES;
        return $wav_type;
    }
    
    # Lookup the wav type by testing the contents of the wav dir.
    foreach my $type (keys %$WAV_TYPES) {
        my $test = File::Spec->catfile(
            $wav_dir,
            $WAV_TYPES->{$type}->{'prefix'}
                   . "*" . $WAV_TYPES->{$type}->{'suffix'}
        );

        my $wav_count = () = glob($test);
        if ($wav_count > 0) {
            say "Found $type batch in $wav_dir";
            return $type;
        }
    }

    die "No wav batch found in $wav_dir\n";
}

sub sanitize {
    local $_ = shift;

    s/ - /-/g;        # Collapse space-dash-space
    s/ /_/g;          # Replace spaces with underscores
    s/(\d+)"/$1in/g;  # Replace 'inch' numbers with string
    s/\&/And/g;       # Replace '&' with 'And'
    s/\//--/g;        # Replace slash with double-dash
    s/[\[\],"'?!.:%#*]//g; # Strip forbidden characters

    return $_;
}

sub init {
    my $config = shift || {};

    my $config_file = $ENV{'MLENCODE_INI'} || "$ENV{'HOME'}/.mlencode.ini";
    $config = mlcommon::load_ini('mlencode', $config, $config_file);

    set_encoded_on($config);
    set_norm_level($config);

    return $config;
}

sub set_encoded_on {
    my $config = shift;

    unless ($config->{'author'}) {
        my $id = `whoami`; chomp $id;
        my $host = `hostname`; chomp $host;
        $config->{'author'} = sprintf("%s@%s", $id, $host);
    }

    my @lt = localtime;
    my $date = sprintf("%02d/%02d/%d", $lt[3], $lt[4] + 1, $lt[5] + 1900);
    $config->{'encoded_on'} = $date . ' by ' . $config->{'author'};

    return $config;
}

sub set_norm_level {
    my $config = shift;

    my $norm_file = File::Spec->catfile(
        (
            $config->{'wav_dir'} || 'disk',
            $config->{'norm_file'} || 'norm_result'
        )
    );
    die "Missing '$norm_file' file\n" unless -e $norm_file;
    die "Empty '$norm_file' file\n" unless -s $norm_file;

    open my $fh, "< $norm_file";
    my $norm_level = <$fh>;
    close $fh;

    chomp $norm_level;
    die "Missing normalization level\n" unless length $norm_level;

    $config->{'norm_level'} = $norm_level;

    return $config;
}

1;
