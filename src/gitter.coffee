{EventEmitter}        = require 'events'
Gitter                = require 'node-gitter'
{Adapter,TextMessage} = require 'hubot'


class GitterAdapter extends Adapter
  # An adapter is a specific interface to a chat source for robots.
  #
  # robot - A Robot instance.
  constructor: (@robot) ->
    super
    @_knownRooms = {}


  # Public: Raw method for sending data back to the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each message to send.
  #
  # Returns nothing.
  send: (envelope, strings...) ->
    if strings.length > 0
      string = strings.shift()
      if typeof(string) is 'function' or string instanceof Function
        string()
        @send envelope, strings...
      else
        # find the room, and send the message to it
        @_resolveRoom(envelope.room, yes, (err, room) =>
          return @_log 'error', "unable to find/join room #{ envelope.room }: #{ err }" if err
          lines = []
          for line in strings
            if line is undefined or line is null
              lines.push ''
            else
              lines.push "#{ line }"
          room.send lines.join '\n'
        )


  # Public: Raw method for sending emote data back to the chat source.
  # Defaults as an alias for send
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each message to send.
  #
  # Returns nothing.
  emote: (envelope, strings...) ->
    @send envelope, strings...


  # Public: Raw method for building a reply and sending it back to the chat
  # source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each reply to send.
  #
  # Returns nothing.
  reply: (envelope, strings...) ->


  # Public: Raw method for setting a topic on the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One more more Strings to set as the topic.
  #
  # Returns nothing.
  topic: (envelope, strings...) ->
    # Gitter does not support setting room topic yet


  # Public: Raw method for playing a sound in the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more strings for each play message to send.
  #
  # Returns nothing
  play: (envelope, strings...) ->
    # Gitter does not support playing sounds yet


  # Public: Raw method for invoking the bot to run. Extend this.
  #
  # Returns nothing.
  run: ->
    token = process.env.HUBOT_GITTER_TOKEN or ''
    rooms = process.env.HUBOT_GITTER_ROOMS or ''
    unless token
      @_log 'error', err = 'you must define HUBOT_GITTER_TOKEN to use Gitter adapter'
      throw new Error(err)
    @gitter = new Gitter(token)
    for uri in rooms.split(/\s*,\s*/g) when uri isnt ''
      @_resolveRoom uri, yes, (err, room) -> @_log 'error', "unable to join room #{ uri }" if err
    @emit 'connected'


  # Public: Raw method for shutting the bot down. Extend this.
  #
  # Returns nothing.
  close: ->


  # Private: Resolve a Gitter room by URI or object, joining it if it is not joined yet
  #
  # uriOrRoom - The room object or its URI
  # join      - Defines whether to join or not the room. Default: false
  # callback  - The method to call when the room is found or if error
  _resolveRoom: (uriOrRoom, join, callback) ->
    if arguments.length < 3
      callback = join
      join = no
    if typeof(uriOrRoom) is 'string' or uriOrRoom instanceof String
      # an URI has been given
      uri = uriOrRoom
      if (room = @_findRoomBy 'uri', uri) and (not join or @_hasJoinedRoom room)
        # we know the room and we joined it already
        callback null, room
      else
        # we didn't join the room yet
        @_joinRoom uri, callback

    else if (id = uriOrRoom?.id)
      # we got a room object
      # this closure will join if needed and finally call our cb
      end = ((room) =>
        if join and not @_hasJoinedRoom(room)
          @_joinRoom room.uri, callback
        else
          callback null, room
      )
      if (room = @_findRoomBy id)
        # we know the room
        end room
      else
        # we try to find the room
        @gitter.rooms.find(id, (err, room) =>
          return callback new Error(err.err) if err
          @_registerRoom room
          end room
        )

    else
      # unrecognized room
      callback new Error("unrecognized room #{ uriOrRoom }")


  # Private: Join a room given its URI
  #
  # uri      - The URI of the room to join
  # callback - The closure to call once joined or in error
  _joinRoom: (uri, callback) ->
    throw new Error("Invalid room URI: #{ uri }") unless uri and (typeof(uri) is 'string' or uri instanceof String)
    @gitter.rooms.join(uri, (err, room) =>
      if err
        @_log 'error', msg = "unable to join room #{ uri }: #{ err.err }"
        callback new Error(msg)
      else
        @_registerRoom room, yes
        callback null, room
    )


  # Private: Register a new known room or update existing one
  #
  # room   - The room object to register or update
  # joined - Whether to register the room as joined/left
  _registerRoom: (room, joined) ->
    throw new Error("invalid room") unless room?.id and room?.uri
    id = "#{room.id}"
    if (r = @_knownRooms[id])
      r.name = room.name
    else
      @_knownRooms[id] = r = room
      r.listen()
    if arguments.length is 2
      @_hasJoinedRoom r, joined
    r



  # Private: Get a known room object with the given property lookup
  #
  # property - The property to look for. Default: 'id'
  # value    - The searched value for that property
  _findRoomBy: (property, value) ->
    if arguments.length is 1
      value = property
      property = 'id'
    if value is undefined or value is null
      undefined
    else if property is 'id'
      @_knownRooms["#{ value }"]
    else
      for room of @_knownRooms when room[property] is value
        return room
      undefined


  # Private: Finds whether we joined the given room yet or not
  #
  # room   - The room object
  # joined - If set, will flag the room as joined or not
  _hasJoinedRoom: (room, joined) ->
    if arguments.length is 2
      if Boolean(joined) isnt Boolean(room._joined)
        # we need to start/stop listening to new messages on that room
        room.events["#{ if joined then 'add' else 'remove' }Listener"] '*', @_handleRoomEvent.bind(@, room)
      room._joined = Boolean joined
    Boolean room._joined


  # Private: Handles a room event
  #
  # room  - The room which received the event
  # event - The event
  _handleRoomEvent: (room, event) ->
    console.log 'ROOM EVENT', room, event


  # Private: log a message (debug by default)
  #
  # level   - The level, default to debug
  # message - The message to log
  _log: (level, message) ->
    if arguments.length is 1
      message = level
      level = 'debug'
    @robot.logger[level] message


exports.use = (robot) -> new GitterAdapter(robot)
