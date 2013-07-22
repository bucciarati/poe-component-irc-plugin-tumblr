package POE::Component::IRC::Plugin::Tumblr;

use strict;
use warnings;

use Data::Dumper;

use POE::Component::IRC;
use POE::Component::IRC::Plugin qw( :ALL );

use WWW::TumblrV2;
use JSON qw( from_json );

my $debug = 0;

sub new {
    my ($package, %args) = @_;

    my $self = bless \%args, $package;

    $self->{tumblr} = WWW::TumblrV2->new(
            %args,
    );

    return $self;
}

sub PCI_register {
    my ($self, $irc) = @_;

    $irc->plugin_register($self, 'SERVER', 'public');

    return 1;
}

sub PCI_unregister {
    return 1;
}

sub S_public {
    my ($self, $irc) = (shift, shift);

    my $nick = ${ +shift };
    $nick =~ s/!.*$//;

    my $channel = shift;
    my $message = shift;

    warn Dumper({
        nick => $nick,
        channel => $channel,
        message => $message,
    }) if $debug;

    unless ( $$message =~ m#(.*) (https?:// [\S]+) (.*)#ix ) {
        return PCI_EAT_NONE;
    }
    my ($pre, $capture_url, $post) = ($1, $2, $3);
    $post =~ s/ \s* \# \s* //x;
    s/^\s+// for $pre, $post;
    s/\s+$// for $pre, $post;
    warn "considering it ($pre)($$message)($post)\n" if $debug;

    my $title = '';
    if ( $pre ){
        $title = "$pre ...";
    }
    if ( $post ){
        $title .= " $post";
    }

    my %post_args = (
        type  => 'text',
        title => $title,
        body  => "&lt;$nick&gt; " . $$message,
    );

    if ( $capture_url =~ m# (https?:// (?:(?:www\.)?youtube\.com | youtu\.be) / \S+ ) #ix ) {
        my $vid_url = $1;

        $post_args{type} = 'video';
        $post_args{embed} = $vid_url;
        $post_args{caption} = "&lt;$nick&gt; " . $$message;

        $irc->yield(
            notice => $$channel,
            "posting Youtube video at '$vid_url'"
        ) if $debug;
    } elsif ( $capture_url =~ m# \. ( jpe?g | gif | png ) \z #ix ) {

        $post_args{type} = 'photo';
        $post_args{caption} = "&lt;$nick&gt; " . $$message;
        $post_args{source} = $capture_url;

        $irc->yield(
            notice => $$channel,
            "posting pic at '$capture_url'"
        ) if $debug;
    } elsif ( $capture_url =~ m# https?://paste\.debian\.net / #ix ) {
        $irc->yield(
            notice => $$channel,
            "posting TEXT message from '$$message'",
        ) if $debug;
    } else {
        $irc->yield(
            notice => $$channel,
            "posting URL in message '$post_args{body}'",
        ) if $debug;
    }

    warn "posting '$post_args{body}'\n" if $debug;

    eval {
        my $post = $self->{tumblr}->post(
            %post_args,
        );

        my $response = from_json( $post );
        my $reply = '';

        if ( $response->{meta}{msg} eq 'Created' ){
            my $id = $response->{response}{id};

            $reply = "Posted at http://$self->{blog}/post/$id",
        } else {
            $reply = "Unrecognized response: [$response]"
        }

        $irc->yield(
            notice => $$channel,
            $reply,
        ) if $self->{reply_with_url};

        1;
    } or do {
        my $error_text = $@;
        chomp $error_text;
        $error_text =~ s/[\r\n]/\\n/g;

        $irc->yield(
            notice => $$channel,
            "->post() error: [$error_text]",
        );
    };

    return PCI_EAT_NONE;
}

1;

__END__

# vim: tabstop=4 shiftwidth=4 expandtab cindent:
