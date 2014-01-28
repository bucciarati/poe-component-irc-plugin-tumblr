#!/usr/bin/env perl

use v5.014;

use strict;
use warnings;
use Data::Dumper ();

# only used when --no-dry-run is not specified
package Fake::Blog;

sub base_hostname { 'yo_moma_dry_run' }

sub post {
    Data::Dumper::Dumper( \@_ );

    return {id => 42};
}

1;

package Fake::IRC;

sub yield {
    say " -NOTICE- @_";
}

1;

package main;

use POE::Component::IRC::Plugin::Tumblr;
use Getopt::Long ();
use File::Basename ();
use YAML::XS ();

my %month_name_to_number = (
    Jan => '01',
    Feb => '02',
    Mar => '03',
    Apr => '04',
    May => '05',
    Jun => '06',
    Jul => '07',
    Aug => '08',
    Sep => '09',
    Oct => '10',
    Nov => '11',
    Dec => '12',
);

sub help {
    if ( @_ ){
        warn " !!! " . $_[0] . " !!!\n\n";
    }

    die <<HELP;
Usage: @{[ File::Basename::basename($0) ]} --config <path_to_pocoirc_config.yaml> --channel <network/channel> [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--throttle 20] irclogs/\\#channel.*.log

  --config          [required] path to pocoirc config file
  --channel         [required] network/channel as specified in the pocoirc config, e.g. "freenode/#bot-test"
  --from            first YYYY-MM-DD to import
  --to              last YYYY-MM-DD to import
  --throttle        how many seconds to sleep between parsing messages
  --no-dry-run      actually submit posts (default is dry-run i.e. don't submit, only show on stdout)

Pass log files as last arguments

Messages are submitted in reverse time order, so the latest URLs will be
submitted first, and you can interrupt the script when it's gone "far back enough"
HELP
};

my ($from, $to);
my $throttle = 10;
my $config;
my $channel_spec = '';
my $no_dry_run;
Getopt::Long::GetOptions(
    'config=s'   => \$config,
    'channel=s'  => \$channel_spec,
    'from=s'     => \$from,
    'to=s'       => \$to,
    'throttle=i' => \$throttle,
    'no-dry-run' => \$no_dry_run,
) or do {
    help();
};

help("Missing option --config is required") unless $config;
help("Missing option --channel is required") unless $channel_spec;

my ($network_name, $channel_name) = split '/', $channel_spec;
help("--channel has to be in network/channel format") unless $network_name && $channel_name;

my $global_config = YAML::XS::LoadFile( $config );
my $network_config = $global_config->{networks}{$network_name};
help("can't find network '$network_name' in config") unless $network_config;

my $plugin_entries = $network_config->{local_plugins};
my ($tumblr_plugin_config) = grep $_->[0] eq 'Tumblr', @$plugin_entries;
help("can't find Tumblr plugin config section") unless @$tumblr_plugin_config;

my $tumblr_api_options = $tumblr_plugin_config->[1];
help("can't find Tumblr API options for channel '$channel_name'") unless $tumblr_api_options->{$channel_name};

sub parse_log_opened {
    my ($text) = @_;

    die "log opened format <$text>?" unless $text =~ /^(?:...) (...) (..) ..:..:.. (....)/;
    my ($mn, $dom, $y) = ($1, $2, $3);
    my $guess = "$y-$month_name_to_number{$mn}-$dom";

    # say "lo mn:$mn dom:$dom y:$y -> $guess";

    return $guess;
}

sub parse_day_changed {
    my ($text) = @_;

    die "day changed format <$text>?" unless $text =~ /^(?:...) (...) (..) (....)/;
    my ($mn, $dom, $y) = ($1, $2, $3);
    my $guess = "$y-$month_name_to_number{$mn}-$dom";

    # say "dc mn:$mn dom:$dom y:$y -> $guess";

    return $guess;
}

my $tumblr =  POE::Component::IRC::Plugin::Tumblr->new( %$tumblr_api_options );

# double negatives
unless ( $no_dry_run ){
    $tumblr->{channel_settings}{$_}{_blog} = bless {}, 'Fake::Blog' for keys $tumblr->{channel_settings};
}

my $fake_irc = bless {}, 'Fake::IRC';

my $day;
my @entries;

while (<>){
    chomp;

    if ( /^--- Log opened (.+)$/ ){
        $day = parse_log_opened($1);
    } elsif ( /^--- Day changed (.+)$/ ){
        $day = parse_day_changed($1);
    }
    next unless $day;

    next if $from && $day lt $from;
    last if $to && $day gt $to;

    if ( /^([0-9]{2}:[0-9]{2}) <.([^>]+)> (.*)$/ ){
        my ($timestamp, $nickname, $text) = ($1, $2, $3);

        unshift @entries, [
            "$day $timestamp:00 GMT",
            \$nickname,
            \$text,
        ];
    }
}

say "@{[ scalar @entries ]} messages to parse";

foreach my $entry_spec ( @entries ){
    $tumblr->{date} = $entry_spec->[0];
    $tumblr->S_public(
        $fake_irc,
        $entry_spec->[1],
        \[$channel_name],
        $entry_spec->[2],
    );

    # be nice to Tumblr, don't machinegun them with posts
    # old logs are old entries anyway
    sleep $throttle;
}

__END__
# vim: tabstop=4 shiftwidth=4 expandtab cindent:
