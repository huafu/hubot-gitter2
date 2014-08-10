hubot-gitter2
=============

### Improved Hubot adapter for Gitter

* * *

There was already one adapter [hubot-gitter](https://github.com/kcjpop/hubot-gitter) but after trying
to fix many missing things from it, I decided to write one from scratch.

[![Gitter chat](https://badges.gitter.im/huafu/hubot-gitter2.png)](https://gitter.im/huafu/hubot-gitter2)

At the time this is written, here is the advantages of this one:

- namespaced environment variables for the configuration
- handling `robot.send room: 'room id or uri', 'my message'`
- gathering information from users in all rooms correctly
- not handling messages that the bot itself is sending


## Installation

- install **Hubot** and **CoffeeScript**: `npm install -g hubot coffeescript`
- create your bot and install its dependencies: `hubot --create my-bot; cd my-bot; npm install`
- save **hubot-gitter2** as dependency: `npm install --save hubot-gitter2`
- start the bot using the right adapter: `HUBOT_GITTER_TOKEN=<your token> HUBOT_GITTER_ROOMS=<room URIs> ./bin/hubot -a gitter2`
    - `HUBOT_GITTER_TOKEN`: get your personal token [there](http://developer.gitter.im) after sign-in
    - `HUBOT_GITTER_ROOMS`: the rooms you want the bot to join (can be an org.: `my-org`, a repo: `user/repo` or a channel: `my-org/channel`)
