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

    my $self = bless \%args, $package;

    $self->{tumblr} = WWW::Tumblr->new(
            %args,
    );
    $self->{blog} = $self->{tumblr}->blog($args{blog});

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

    my $text = $$message;
    Encode::_utf8_on( $text );

    unless ( $text =~ m#(.*) (https?:// [\S]+) (.*)#ix ) {
        return PCI_EAT_NONE;
    }
    my ($pre, $capture_url, $post) = ($1, $2, $3);
    $post =~ s/ \s* \# \s* //x;
    s/^\s+//, s/\s+$// for $pre, $post;
    warn "considering it ($pre)($text)($post)\n" if $self->{debug};

    my $title = '';
    if ( $pre ){
        $title = "$pre ...";
    }
    if ( $post ){
        $title .= " $post";
    }
    s/^\s+//, s/\s+$// for $title;

    my %post_args = (
        type  => 'text',
        title => $title,
        body  => "<$nick> $text",
        caption => "<$nick> $text",

        # make it possible to import old entries from e.g. logs
        # see e.g. contrib/log-importer-irssi.pl for an usage
        exists $self->{date} ? ( date => $self->{date} ) : (),
    );

    if ( $capture_url =~ m# (https?:// (?:(?:www\.)?youtube\.com | youtu\.be) / \S+ ) #ix ) {
        my $vid_url = $1;

        $post_args{type} = 'video';
        $post_args{embed} = $vid_url;
    } elsif ( $capture_url =~ m# \. ( jpe?g | gif | png ) \z #ix ) {

        $post_args{type} = 'photo';
        $post_args{source} = $capture_url;
    }

    $post_args{$_} = HTML::Entities::encode_entities($post_args{$_}) for qw(
        title
        body
        caption
    );
    warn "posting <@{[ Dumper(\%post_args) ]}>\n" if $self->{debug};

    eval {
        my $response = $self->{blog}->post(
            %post_args,
        );

        if ( my $id = $response->{id} ){
            # seems to have succeeded
            $irc->yield(
                notice => $$channel,
                "Posted at http://@{[ $self->{blog}->base_hostname ]}/post/$id",
            ) if $self->{reply_with_url};
        } elsif ( my $error = $self->{blog}->error ) {
            # posting big (>2MB) .gifs tends to fail;  retry as a text post
            if ( $post_args{type} eq 'photo' ) {
                $post_args{type} = 'text';

                my $retry_response = $self->{blog}->post(
                    %post_args,
                );

                if ( my $retry_error = $self->{blog}->error ) {
                    $irc->yield(
                        notice => $$channel,
                        "Tumblr returned an error while posting: [@{ $error->reasons }] and while re-posting: [@{ $retry_error->reasons }]"
                    );
                }
            } else {
                $irc->yield(
                    notice => $$channel,
                    "Tumblr returned an error while posting: [@{ $error->reasons }]"
                );
            }
        } else {
            my $debug = Data::Dumper::Dumper( $response );
            $debug =~ s/\n/ /g;

            $irc->yield(
                notice => $$channel,
                "Unrecognized response: [$debug]"
            );
        }

        1;
    } or do {
        my $error_text = $@;
        chomp $error_text;
        $error_text =~ s/[\r\n]/\\n/g;

        $irc->yield(
            notice => $$channel,
            "->post() died: [$error_text]",
        );
    };

    return PCI_EAT_NONE;
}

1;

__END__

# vim: tabstop=4 shiftwidth=4 expandtab cindent:
