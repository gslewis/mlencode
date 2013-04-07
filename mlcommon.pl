#!/usr/bin/perl -w
package mlcommon;

sub load_ini {
    my $section = shift;
    my $config = shift || {};
    my $config_file = shift;

    my $common_section = 1;
    my $in_section = 0;

    open (INPUT, $config_file) or die "Failed to open $config_file: $!";
    while (<INPUT>) {
        chomp;
        next if /^;/ || /^\s*$/;

        # We are in the common section until we hit the first section title.
        # Can have multiple sections with the same title (but why bother).
        if (/^\[(\w+)\]\s*$/) {
            $common_section = 0;
            $in_section = $1 eq $section;
            next;
        }

        if ($common_section || $in_section) {
            my ($key, $value) = split(/\s*=\s*/);

            # Check for key in format: key[index] = value
            if ($key =~ /^\s*(\w+)\[(\w+)\]$/) {
                $key = $1;
                $index = $2;

                $config->{$key} = {} unless exists($config->{$key});
                $config->{$key}->{$index} = $value;

            } else {
                $config->{$key} = $value;
            }
        }
    }
    close(INPUT);

    return $config;
}

sub get_album_data {
    my $data_file = shift;

    my %data = ();
    my @tracks = ();

    open my $fh, "< $data_file" or die "Failed to open $data_file: $!";
    while (<$fh>) {
        chomp;
        next if /^\s*$/;
        next if /^#/;

        if (/^(BAND|ARTIST)=(.*)$/i) {
            $data{'artist'} = $2;
        } elsif (/^ALBUM=(.*)$/i) {
            $data{'album'} = $1;
        } elsif (/^YEAR=(.*)$/i) {
            $data{'year'} = $1;
        } else {
            push @tracks, $_;
        }
    }
    close $fh;

    my @missing = ();
    push @missing, 'artist' unless $data{'artist'};
    push @missing, 'album' unless $data{'album'};
    push @missing, 'year' unless $data{'year'};
    push @missing, 'tracks' unless @tracks > 0;
    if (@missing > 0) {
        die "Album data missing " . join(', ', @missing) . "\n";
    }

    $data{'tracks'} = \@tracks;

    return \%data;
}

sub get_track_data {
    my $_ = shift;

    my %data = map { $_ => undef; } qw(artist album track);

    # Can specify per-track artist and album using the '@@' and '%%'
    # separators:
    #
    #   track
    #   artist@@track
    #   album%%track
    #   artist@@album%%track

    if (/^(.+)@@(.*)%%(.*)$/) {
        $data{'artist'} = $1;
        $data{'album'} = $2;
        $data{'track'} = $3;
    } elsif (/^(.+)@@(.+)$/) {
        $data{'artist'} = $1;
        $data{'track'} = $2;
    } elsif (/^(.+)%%(.+)$/) {
        $data{'album'} = $1;
        $data{'track'} = $2;
    } else {
        $data{'track'} = $_;
    }

    return \%data;
}

1;
