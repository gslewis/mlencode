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

1;
