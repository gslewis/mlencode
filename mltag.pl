#!/usr/bin/perl -w
package mltag;

=head1 NAME

mltag.pl - Re-tags files from updated data.

=head1 SYNOPSIS

    mltag.pl path/to/album/directory

    mltag.pl path/to/album/directory/data

The argument should identify the 'data' file containing the tag values.

=cut

use 5.012;
use strict;
use File::Copy;
use File::Spec;
use File::Path;
use Cwd;
use Data::Dumper; # REMOVE

require 'mlcommon.pl';

my $config_file = $ENV{'MLENCODE_INI'} || "$ENV{'HOME'}/.mlencode.ini";
my $config = {};

$config = mlcommon::load_ini('mltag', $config, $config_file);

# Locate the 'data' file containing the new tags to apply.
# We assume the data file is in the directory containing the music files.
# 1. If no arg, look in working directory.
# 2. If arg is directory, look in directory
# 3. Else try arg as the data file.
my $data_file;
if (@ARGV == 0) {
    $data_file = File::Spec->catfile(getcwd(), "data");
} elsif (-d $ARGV[0]) {
    $data_file = File::Spec->catfile($ARGV[0], "data");
} else {
    $data_file = $ARGV[0];
}
die "No such 'data' file: $data_file\n" unless -f $data_file;

# TODO: Account for $volume.
my $album_dir = (File::Spec->splitpath($data_file))[1];
my @files = glob($album_dir . "*");

# Assumes audio files are of form '01_Title.format' so will appear in numeric
# order from glob().  As the globbed files are in numeric order, they will
# match the track order from the 'data' file.
die "Unsupported audio format in $album_dir\n"
    unless $files[0] =~ /\.(flac|mp3|ogg|wv)$/;
my $format = $1;

my $album_data = mlcommon::get_album_data($data_file);

# For each file with the matching format...
my $index = 0;
my $change_count = 0;
for my $file (@files) {
    my ($filename) = (File::Spec->splitpath($file))[2];
    next unless $filename =~ /\.$format$/;

    # Extract the current tags from the audio file.  The tags we can modify
    # are 'title', 'artist', 'album' and 'year' and should be returned with
    # those keys, even if the audio file's tag has a different name.  All
    # other tags should be returned as is and will be reinstated without
    # modification.
    my $tags = undef;
    eval {
        no strict 'refs';
        my $fn = "get_tags_$format";
        $tags = &$fn($file);
    };
    die $@ if $@;

    # Get the corresponding track data.  Assumes globbed files are in numeric
    # order.
    my $track_data =
        mlcommon::get_track_data($album_data->{'tracks'}->[$index]);

    # Establish the new tags that we can change.
    my $new_tags = {
        'title' => $track_data->{'track'},
        'artist' => $track_data->{'artist'} || $album_data->{'artist'},
        'album' => $track_data->{'album'} || $album_data->{'album'},
        'year' => $album_data->{'year'}
    };

    # Identify the tags that have been modified.
    my @changed = update_tags($tags, $new_tags);

    if (scalar(@changed)) {
        eval {
            no strict 'refs';
            my $fn = "set_tags_$format";
            &$fn($file, $tags, \@changed);
            ++$change_count;
        };
        die $@ if $@;
    }

    ++$index;
}

say "No tag changes detected in $album_dir" unless $change_count;

1;

sub update_tags {
    my ($tags, $new_tags) = @_;

    my @changed = ();

    for my $tag (keys %$new_tags) {
        if ($tags->{$tag} ne $new_tags->{$tag}) {
            $tags->{$tag} = $new_tags->{$tag};
            push @changed, $tag;
        }
    }

    return @changed;
}

sub get_tags_ogg {
    my $file = shift;

    my %tags = map {
        chomp;
        split /=/, $_;
    } `vorbiscomment --list "$file"`;

    $tags{'year'} = delete $tags{'date'};

    return \%tags;
}

sub set_tags_ogg {
    my ($file, $tags, $changed) = @_;

    # Need to pass all tags, changed and unchanged.
    my @cmd = qw(vorbiscomment --quiet --write);
    for my $tag (keys %$tags) {
        my $name = $tag eq 'year' ? 'date' : $tag;
        my $value = $tags->{$tag};

        push @cmd, ('--tag', "$name=$value");
    }

    push @cmd, $file;

    say "Modified " . join(', ', @$changed) . " in $file";
    system @cmd;
}

sub get_tags_flac {
    my $file = shift;

    my %tags = map {
        chomp;
        split /=/, $_;
    } `metaflac --export-tags-to=- "$file"`;

    $tags{'year'} = delete $tags{'date'};

    return \%tags;
}

sub set_tags_flac {
    my ($file, $tags, $changed) = @_;

    # Remove all tags (changed or otherwise) and re-import all.  Otherwise if
    # we just import the changed tags, we need to remove them first.
    open(my $fh, "|-", "metaflac --remove-all-tags --import-tags-from=- \"$file\"")
        or die "Could not fork: $!\n";

    # Only need to pass changed tags.  Other tags are unmodified.
    for my $tag (keys %$tags) {
        my $name = $tag eq 'year' ? 'date' : $tag;
        my $value = $tags->{$tag};

        print $fh "$name=$value\n";
    }
    close($fh) or die "Could not close: $!\n";

    say "Modified " . join(', ', @$changed) . " in $file";
}
