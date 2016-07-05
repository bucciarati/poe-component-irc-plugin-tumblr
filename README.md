POE::Component::IRC::Plugin::Tumblr
===================================

This `POE::Component::IRC` plugin makes it trivial for IRC bots to sit on your channel and use the [Tumblr API](http://www.tumblr.com/docs/en/api/v2) (via `WWW::Tumblr` ([github](https://github.com/damog/www-tumblr), [metacpan](https://metacpan.org/pod/WWW::Tumblr))) to log any public message mentioning HTTP or HTTPS links.  Note that you'll need to get OAuth tokens for your bot, which Tumblr makes [quite simple](http://www.tumblr.com/oauth/apps) once you're logged in.

There's specific support for:
 - Youtube and Vimeo video URLs which will be posted as "video" blog entries
 - image links (guessed by the URL) which will be posted as "photo" blog entries
 - posting changes to topic

and all other URLs will be posted as "text" blog entries.  In all cases the text around the link will be used as post title/caption/body depending on the entry type.

All posts can be tagged.  An example is worth more than one thousand words:

    13:37 < Bucciarati> check this [awesome] [wm] out http://awesome.naquadah.org/ it's what I currently use

... will post a text entry tagged "awesome" and "wm".

Using the `[OTR]` ("off the record") tag will prevent the bot from posting anything (for when you're posting some link that you don't want to have published on Tumblr).

Configuration
=============

Here's an example [pocoirc](https://metacpan.org/pod/App::Pocoirc) configuration to get you started:

```YAML
networks:
    freenode:
        server: chat.freenode.net
        local_plugins:
            # Connector and AutoJoin not strictly required, but here for
            # completeness since most people will want those
            - [Connector, { reconnect: 30 }]
            - [AutoJoin, { Channels: ['#me-and-my-friends', '##other-channel'] }]

            - [Tumblr, {
                  '#me-and-my-friends': {
                      # Required.
                      blog: 'thischannel.tumblr.com',

                      # Required.  Register your app and get your
                      # OAuth tokens from http://www.tumblr.com/oauth/apps
                      consumer_key: '...',
                      secret_key: '...',
                      token: '...',
                      token_secret: '...',

                      # All of the following are optional.
                      reply_with_url: true,   # defaults to false
                      debug: true,            # defaults to false
                      hide_nicks:   'mapfile',                  # defaults to not being set
                      nick_mapfile: '/usr/share/dict/english',  # only makes sense when hide_nicks is 'mapfile'
                  },
                  '##other-channel': {
                      # ... config for another channel
                  },
              }]
```

When `reply_with_url` is true, the bot will reply with the post URL, like so:

    04:29 <@Bucciarati> http://www.cs.berkeley.edu/~necula/cil/cil016.html
    04:29 -bottana:##channel- Posted at http://thischannel.tumblr.com/post/42743921926

(needless to say, this gets tedious when many links get posted to a channel, so it defaults to false).

When `debug` is true, the bot will output various diagnostic messages to the console.  As the name suggests, it's only useful for debugging/troubleshooting.

When `hide_nicks` is not specified, the bot will use the actual IRC nicknames in the post.

When `hide_nicks` is `mapfile`, it will use the lines of `nick_mapfile` to conceal the identity of the poster.

About
=====

This code lives at https://github.com/bucciarati/poe-component-irc-plugin-tumblr and is mostly developed and taken care of during those rainy insomniac nights when the bot is the only one paying attention to IRC.

Note: This code and its author are in no way affiliated with Tumblr nor Yahoo! Inc.
