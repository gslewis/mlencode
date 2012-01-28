#!/usr/bin/perl -w
my $count = 0;
foreach my $file (glob("*.flac")) {
    system('flac', '-d', '-o', sprintf("track%02d.cdda.wav", ++$count), $file);
}
