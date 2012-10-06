Music Library Scripts
=====================

Geoff Lewis <http://github.com/gslewis/mlencode>

A set of scripts for managing my digital music libraries:

* mlrip.pl      - rips single- or multi-disk albums to normalized wavs
* mlencode.pl   - encodes wavs to ogg, mp3 or flac
* mladdalbum.pl - adds an album to a local device library using hard links
* mlsync.pl     - synchronizes a local device library to its player
* mlcommon.pl   - shared functions
* flac2wav.pl   - creates wavs from flac using cdparanoia naming scheme

The idea is that I have my central music library plus a number of portable
music players.  Each player has its own local library containing hard links to
tracks in the central library.  By adding (hard linking) & deleting albums &
tracks in the local libraries, then using rsync between the local library and
the mounted player, I can maintain the contents of my players.

Configured by the ~/.mlencode.ini configuration file.  Copy the mlencode.ini
sample configuration file and modify as required.

The main scripts contain basic documentation comments in perldoc format.

Licence
-------
All files are public domain (2011-2012)

Geoff Lewis <gsl@gslsrc.net>
