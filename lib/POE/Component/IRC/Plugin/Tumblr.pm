package POE::Component::IRC::Plugin::Tumblr;

use strict;
use warnings;

use Data::Dumper;

use POE::Component::IRC;
use POE::Component::IRC::Plugin qw( :ALL );

use HTML::Entities ();
use Encode ();

use WWW::Tumblr;
use JSON qw( from_json );

sub new {
    my ($package, %args) = @_;

    my $self = bless {}, $package;

    for my $channel_name ( keys %args ){
        my $lc_channel_name = lc $channel_name;

        my $this_channel_settings = ($self->{channel_settings}{$lc_channel_name} = {});

        $this_channel_settings->{_tumblr} = WWW::Tumblr->new(
            consumer_key => $args{$channel_name}->{consumer_key},
            secret_key   => $args{$channel_name}->{secret_key},
            token        => $args{$channel_name}->{token},
            token_secret => $args{$channel_name}->{token_secret},
        );

        $this_channel_settings->{_blog} = $this_channel_settings->{_tumblr}->blog($args{$channel_name}->{blog});

        $this_channel_settings->{debug}          = $args{$channel_name}->{debug};
        $this_channel_settings->{debug_channel}  = $args{$channel_name}->{debug_channel};
        $this_channel_settings->{reply_with_url} = $args{$channel_name}->{reply_with_url};
        $this_channel_settings->{hide_nicks}     = $args{$channel_name}->{hide_nicks};
        $this_channel_settings->{nick_mapfile}   = $args{$channel_name}->{nick_mapfile};
        $this_channel_settings->{nick_map}       = $args{$channel_name}->{nick_map} || {};
        $this_channel_settings->{preserve_nicks_in_context} = $args{$channel_name}->{preserve_nicks_in_context};

        $this_channel_settings->{otr_support} = exists $args{$channel_name}->{otr_support}
            ? $args{$channel_name}->{otr_support}
            : 1;

        $this_channel_settings->{otr_url_regexes} = exists $args{$channel_name}->{otr_url_regexes}
            ? [ map qr($_), @{ $args{$channel_name}->{otr_url_regexes} } ]
            : [];
    }

    foreach my $channel_name ( sort keys %{$self->{channel_settings}} ){
        my $channel_settings = $self->{channel_settings}{$channel_name};
        my $base_hostname = $channel_settings->{_blog}->base_hostname;

        if ( my $hiding_method = $channel_settings->{hide_nicks} ){
            if ( $hiding_method eq 'mapfile' ){
                my $mapfile = $channel_settings->{nick_mapfile};
                warn "loading $channel_name nick_mapfile from '$mapfile'\n" if $channel_settings->{debug};

                open my $fh, '<', $mapfile;
                while (my $line = <$fh>) {
                    chomp $line;
                    my $initial = lc substr($line, 0, 1);

                    push @{ $channel_settings->{_nick_mapfile}{$initial} }, $line;
                }
                $fh->close;
            } elsif ($hiding_method eq 'map'){
                my $map = $channel_settings->{nick_map};
            } else {
                warn "Posts to $base_hostname will be from <Anonymous>\n" if $channel_settings->{debug};
            }
        }

        next unless $channel_settings->{debug};

        my @settings_to_dump = sort grep !/\A_/, keys %$channel_settings;
        warn "API for $channel_name -> $base_hostname (",
            (join ', ', map( $_ . ":" . ($channel_settings->{$_} || 0), @settings_to_dump )),
        ")\n";
    }

    return $self;
}

sub _nick_from_map {
    my ($channel_settings, $original_nick) = @_;

    my $map_method = $channel_settings->{hide_nicks};
    my $obfuscated_nick = ({
        'map' => sub {
            my $map = $channel_settings->{nick_map};

            return $map->{lc $original_nick} || 'Guest';
        },
        'mapfile' => sub {
            my $initial = lc substr($original_nick, 0, 1);
            my $map = $channel_settings->{_nick_mapfile};

            return "$initial***" unless
                exists $map->{$initial}
                && ref $map->{$initial} eq 'ARRAY'
                && scalar @{ $map->{$initial} };

            my $i = int(rand() * scalar @{ $map->{$initial} });

            # warn $initial, ' ', $i, ' ', scalar @{ $map->{$initial} }, "\n";

            return $map->{$initial}->[$i];
        },
    }->{$map_method} || sub {'Anonymous'})->();

    return $obfuscated_nick;
}

sub _debug {
    my ($self, $irc, $channel, $message) = @_;

    my $lc_channel = lc $channel;
    my $channel_settings = $self->{channel_settings}{$lc_channel};

    return unless $channel_settings->{debug};

    if ( ref $message ){
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Indent = 0;
        $message = Data::Dumper::Dumper( $message );
    }
    $message =~ s/\n/ /g;

    if ( my $debug_channel = $channel_settings->{debug_channel} ){
        $lc_channel = $debug_channel;

        $irc->yield(
            notice => $lc_channel,
            $message
        );
    } else {
        warn "[$lc_channel] $message\n";
    }
}

sub PCI_register {
    my ($self, $irc) = @_;

    $irc->plugin_register($self, 'SERVER', 'public');
    $irc->plugin_register($self, 'SERVER', 'ctcp_action');
    $irc->plugin_register($self, 'SERVER', 'topic');

    # uncomment to discover signal names
    # $irc->plugin_register($self, 'SERVER', 'all');

    return 1;
}

sub PCI_unregister {
    return 1;
}

sub _default {
    my ($self, $irc, $event) = (shift, shift, shift);
    warn "[w] _default called for <$event>\n";
    my $channel = ${ +shift };
    $self->_debug($irc, $channel, "_default called for <$event> on <$channel>");
    return PCI_EAT_NONE;
}

sub S_ctcp_action {
    goto \&S_public;
}

sub S_public {
    my ($self, $irc) = (shift, shift);

    my $nick = ${ +shift };
    $nick =~ s/!.*$//;

    my $channel = ${ +shift }->[0];
    my $lc_channel = lc $channel;
    my $channel_settings = $self->{channel_settings}{$lc_channel};

    my $message = shift;

    my $text = $$message;
    Encode::_utf8_on( $text );

    if ( $channel_settings->{hide_nicks} ){
        $nick = _nick_from_map( $channel_settings, $nick );
    }
    Encode::_utf8_on( $nick );

    # make it possible to import old entries from e.g. irssi logs
    # see e.g. contrib/log-importer-irssi.pl for an example usage
    print "$self->{date} <$nick> $text\n" if $self->{date};

    # normalize from spotify http/https link to spotify: uri
    $text =~ s#\b https?://open\.spotify\.com/track/([[:alnum:]]+) \b #spotify:track:$1#ixg;

    # TODO: http://open.spotify.com/track/48WNlfPjunceFkIQq7z0bV -> spotify:track:48WNlfPjunceFkIQq7z0bV
    # spotify:(album|artist|track)
    if ( $text =~ m# \b (spotify:[^:]+:[a-zA-Z0-9]+) \b #ix ){
        my $capture_url = $1;
        $self->_debug($irc, $channel, "spotify-captured <$capture_url>");
        my %args = (
            type => 'text',
            format => 'html',
            body => qq[<iframe src="https://embed.spotify.com/?uri=$capture_url" width="300" height="380" frameborder="0" allowtransparency="true"></iframe>],
        );

        # XXX this posts without context
        $channel_settings->{_blog}->post(
            %args
        );
    }

    unless ( $text =~ m#(.*) (https?:// [\S]+) (.*)#ix ) {
        return PCI_EAT_NONE;
    }
    my ($pre, $capture_url, $post) = ($1, $2, $3);
    $post =~ s/ \s* \# \s* //x;
    s/^\s+//, s/\s+$// for $pre, $post;
    $self->_debug($irc, $channel, "considering it ($pre)($text)($post)");

    for my $otr_url_regex ( @{ $channel_settings->{otr_url_regexes} } ){
        if ( $capture_url =~ $otr_url_regex ){
            $self->_debug($irc, $channel, "url <$capture_url> matches <$otr_url_regex>");
            return PCI_EAT_NONE;
        }
    }

    my $title = '';
    if ( $pre ){
        $title = "$pre ...";
    }
    if ( $post ){
        $title .= " $post";
    }
    s/^\s+//, s/\s+$// for $title;

    my $tags_spec = '';
    if ( my @tags = $title =~ / \[ ([^\]]+) \] /gix ){
        # a tag of [otr] (case insensitive) means that we
        # should *NOT* publish the URL, it's off the record.
        if ( $channel_settings->{otr_support} && grep +(lc $_ eq "otr"), @tags ){
            return PCI_EAT_NONE;
        }

        $tags_spec = join ',', @tags;
    }

    unless ( $channel_settings->{preserve_nicks_in_context} ){
        my $bot_name = $irc->nick_name;
        foreach my $someones_nick_name ( $irc->channel_list( $lc_channel ) ){
            $text =~ s/\Q$someones_nick_name\E/$bot_name/ig;
        }
    }

    my %post_args = (
        type  => 'text',
        body  => "<$nick> $text",
        caption => "<$nick> $text",
        tags  => $tags_spec,

        # make it possible to import old entries from e.g. irssi logs
        # see e.g. contrib/log-importer-irssi.pl for an example usage
        exists $self->{date} ? ( date => $self->{date} ) : (),
    );

    if (
        $capture_url =~ m# ( https?:// (?:(?:www\.)? youtube\.com ) /watch \b \S+ ) #ix
     || $capture_url =~ m# ( https?:// (?: youtu\.be ) / \S+ ) #ix
     || $capture_url =~ m# ( https?:// vimeo\.com / \S+ ) #ix
    ) {
        my $vid_url = $1;

        $post_args{type} = 'video';
        $post_args{embed} = $vid_url;
    } elsif ( $capture_url =~ m# \. ( jpe?g | gif | png ) (?::large)? (?:\?.*)? \z #ix ) {

        $post_args{type} = 'photo';
        $post_args{source} = $capture_url;
    }

    $post_args{$_} = HTML::Entities::encode_entities($post_args{$_}) for qw(
        body
        caption
        tags
    );
    $self->_debug( $irc, $lc_channel, "posting <@{[ Dumper(\%post_args) ]}>\n" );

    eval {
        my $response = $channel_settings->{_blog}->post(
            %post_args,
        );

        if ( my $id = $response->{id} ){
            # seems to have succeeded
            $irc->yield(
                notice => $channel,
                "Posted at http://@{[ $channel_settings->{_blog}->base_hostname ]}/post/$id",
            ) if $channel_settings->{reply_with_url};
        } elsif ( my $error = $channel_settings->{_blog}->error ) {
            # Things that fail:
            # - posting big (>2MB) .gifs
            # - posting resources with non-image Content-Type
            # so, we retry failed image posts as text posts
            if ( $post_args{type} eq 'photo' ) {
                $post_args{type} = 'text';

                $self->_debug($irc, $lc_channel, "re-posting <@{[ Dumper(\%post_args) ]}>");
                my $retry_response = $channel_settings->{_blog}->post(
                    %post_args,
                );

                if ( my $id = $retry_response->{id} ) {
                    # seems to have succeeded
                    $irc->yield(
                        notice => $channel,
                        "Posted at http://@{[ $channel_settings->{_blog}->base_hostname ]}/post/$id",
                    ) if $channel_settings->{reply_with_url};
                } elsif ( my $retry_error = $channel_settings->{_blog}->error ) {
                    $irc->yield(
                        notice => $channel,
                        "Tumblr returned an error while posting: [@{ $error->reasons }] and while re-posting: [@{ $retry_error->reasons }]"
                    );
                }
            } else {
                $irc->yield(
                    notice => $channel,
                    "Tumblr returned an error while posting: [@{ $error->reasons }]"
                );

                $self->_debug( $irc, $channel, { response => $response, error => $error } );
            }
        } else {
            my $debug = Data::Dumper::Dumper( $response );
            $debug =~ s/\n/ /g;

            $irc->yield(
                notice => $channel,
                "Unrecognized response: [$debug]"
            );
        }

        1;
    } or do {
        my $error_text = $@;
        chomp $error_text;
        $error_text =~ s/[\r\n]/\\n/g;

        $irc->yield(
            notice => $channel,
            "->post() died: [$error_text]",
        );
    };

    return PCI_EAT_NONE;
}

sub S_topic {
    my ($self, $irc) = (shift, shift);

    my $nick = ${ +shift };
    $nick =~ s/!.*$//;

    my $channel = ${+shift};
    my $lc_channel = lc $channel;
    my $channel_settings = $self->{channel_settings}{$lc_channel};

    my $message = shift;

    my $text = $$message;
    Encode::_utf8_on( $text );

    $self->_debug($irc, $channel, "topic on <$lc_channel> set by <$nick> to <$text>");

    my %post_args = (
        type  => 'text',
        body  => "$text",
        caption => "$text",
        tags => 'topic',
    );

    $post_args{$_} = HTML::Entities::encode_entities($post_args{$_}) for qw(
        body
        caption
    );
    $self->_debug($irc, $lc_channel, "posting <@{[ Dumper(\%post_args) ]}>");

    my $response = $channel_settings->{_blog}->post(
        %post_args,
    );

    if ( my $id = $response->{id} ){
        # seems to have succeeded
        $irc->yield(
            notice => $channel,
            "Posted at http://@{[ $channel_settings->{_blog}->base_hostname ]}/post/$id",
        ) if $channel_settings->{reply_with_url};
    }

    return PCI_EAT_NONE;
}

1;

__END__

# vim: tabstop=4 shiftwidth=4 expandtab cindent:
