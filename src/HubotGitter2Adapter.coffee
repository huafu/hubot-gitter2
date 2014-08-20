{Adapter,TextMessage} = require 'hubot'
GitterObject          = require './GitterObject'
GitterClient          = require './GitterClient'
GitterUser            = require './GitterUser'
GitterRoom            = require './GitterRoom'


# The hubot adapter for gitter
class HubotGitter2Adapter extends Adapter

  # @property {RegExp} The regexp used to find if the given string is a valid room id
  @ROOM_ID_REGEXP: /^[a-f0-9]{24}$/

  # @property {GitterClient} Our client
  _client: null


  # An adapter is a specific interface to a chat source for robots.
  #
  # @param {Robot} robot A Robot instance.
  constructor: (@robot) ->
    GitterObject.LOGGER_FALLBACK_METHOD_NAME = 'info'
    GitterObject._logger = @robot.logger
    super


  # Raw method for sending data back to the chat source. Extend this.
  #
  # @param {Object} envelope A Object with message, room and user details.
  # @param {Array<String>} strings One or more Strings for each message to send.
  send: (envelope, strings...) ->
    @_resolveRoom(envelope.room, yes, (room) =>
      room.asyncSend strings
    )
    return


  # Raw method for sending emote data back to the chat source.
  # Defaults as an alias for send
  #
  # @param {Object} envelope A Object with message, room and user details.
  # @param {Array<String>} strings One or more Strings for each message to send.
  emote: (envelope, strings...) ->
    @send envelope, strings...


  # Raw method for building a reply and sending it back to the chat
  # source. Extend this.
  #
  # @param {Object} envelope A Object with message, room and user details.
  # @param {Array<String>} strings One or more Strings for each reply to send.
  #
  # Returns nothing.
  reply: (envelope, strings...) ->
    room = envelope.room or envelope.message?.room or envelope.message?.user?.room or envelope.user?.room
    if room
      @send {room}, strings...
    else
      @_log 'error', "failed to reply: #{ GitterObject.inspectArgs arguments }"
    return


  # Raw method for setting a topic on the chat source. Extend this.
  #
  # @param {Object} envelope A Object with message, room and user details.
  # @param {Array<String>} strings One more more Strings to set as the topic.
  topic: (envelope, strings...) ->
    # Gitter does not support setting room topic yet


  # Raw method for playing a sound in the chat source. Extend this.
  #
  # @param {Object} envelope A Object with message, room and user details.
  # @param {Array<String>} strings One or more strings for each play message to send.
  play: (envelope, strings...) ->
    # Gitter does not support playing sounds yet


  # Raw method for invoking the bot to run. Extend this.
  run: ->
    # joining rooms
    cl = @gitterClient()
    cl.on "GitterUser.create", (user) =>
      @_registerUser user
    cl.on 'ready', (duration) =>
      cl.sessionUser().asyncRooms (error, rooms) =>
        if error
          @_log 'error', "error while getting rooms: #{ error }"
        else
          self = @
          for room in rooms
            # be sure to load users of the room
            room.asyncUsers()
            room.isListening yes
            room.on 'chatMessages.*', ((room) ->
              -> self._handleChatMessage @event, room, arguments...
            )(room)
          @emit 'connected'


  # Raw method for shutting the bot down. Extend this.
  close: ->
    cl = @gitterClient()
    cl.off '*'
    cl.disconnect (error) =>
      if error
        @_log 'error', "error while disconnecting: #{ error }"
      else
        @_client = null

  # Get our core client, creating it if necessary
  #
  # @return {GitterClient} The core client
  gitterClient: ->
    unless @_client
      token = process.env.HUBOT_GITTER2_TOKEN or process.env.HUBOT_GITTER_TOKEN or ''
      unless token
        @_log 'error', err = 'you must define HUBOT_GITTER2_TOKEN to use Gitter adapter'
        throw new Error(err)
      @_client = GitterClient.factory {token}
    @_client


  # Resolve a Gitter room by URI or object, joining it if it is not joined yet
  #
  # @param {String, Object} uriOrRoom The room description, or its URI, or its ID
  # @param {Boolean} join Defines whether to join or not the room. Default: false
  # @param {Function} callback The method to call when the room is found
  _resolveRoom: (uriOrRoom, join, callback) ->
    if arguments.length < 3
      callback = join
      join = no
    if typeof(uriOrRoom) is 'string' or uriOrRoom instanceof String
      if HubotGitter2Adapter.ROOM_ID_REGEXP.test(uriOrRoom)
        # it is a room ID
        uriOrRoom = id: uriOrRoom
      else
        # an URI has been given
        uriOrRoom = uri: uriOrRoom
    try
      @gitterClient().asyncRoom(uriOrRoom, (error, room) =>
        if error
          @_log 'error', error
        else
          if join and not room.hasJoined()
            room.asyncJoin (error) =>
              if error
                @_log 'error', error
              else
                callback room
          else
            callback room
      )
    catch error
      @_log 'error', error

  # Handles a room message event
  #
  # @param {GitterRoom} room The room where the event triggered
  # @param {Object} event The event object, with `operation` and `model`, last one being the message itself
  _handleChatMessage: (eventName, room, data) ->
    if eventName is 'chatMessages.chatMessages' and data.operation is 'create'
      message = data.model
      cl = @gitterClient()
      cl.asyncUser message.fromUser, (error, user) =>
        if error
          @_log 'error', "error loading a user: #{ error }"
        else if user.isSessionUser()
          @_log "not handling a message from the bot user"
        else if @_ignoreRoom(room)
          @_log "not handling a message because in room #{ room }"
        else
          sender = @_hubotUser user
          sender.room = room.id()
          msg = new TextMessage sender, message.text, message.id
          msg.private = room.isOneToOne()
          try
            @robot.receive msg
            @_log "handled message #{ msg.id } in room #{ room }"
          catch err
            @_log 'error', "error handling message #{ msg.id }: #{ err }"
    # be sure to not return anything
    return


  # Log a message (debug by default)
  #
  # @param {String} level The level, default to debug
  # @param {String} message The message to log
  _log: (level, message) ->
    if arguments.length is 1
      message = level
      level = 'debug'
    @robot.logger[level] "[hubot-gitter2.#{ level }] #{ message }"


  # Should we ignore message from the given room
  #
  # @param {GitterRoom} room The room to test
  # @return {Boolean} Returns `true` if the room should be ignored, else `false`
  _ignoreRoom: (room) ->
    if (list = process.env.HUBOT_GITTER2_TESTING_ROOMS) and list = list.split(/\s*,\s*/g)
      room.prettyIdentifier() not in list
    else if (list = process.env.HUBOT_GITTER2_IGNORE_ROOMS) and list = list.split(/\s*,\s*/g)
      room.prettyIdentifier() in list
    else
      no


  # Get the hubot user for the given GitterUser
  #
  # @param {GitterUser} user The core GitterUser
  # @return {User} The hubot user object
  _hubotUser: (user) ->
    @robot.brain.userForId(user.id())


  # Register a user in the robot's brain
  #
  # @param {GitterUser} user The user to register
  _registerUser: (user) ->
    robotUser = @robot.brain.userForId(user.id())
    update = ->
      name = []
      name.push dn if (dn = user.displayName())
      name.push "(#{ n })" if (n = user.login()) and not dn or n.toLowerCase() isnt dn.toLowerCase()
      d =
        login: user.login()
        name: if name.length then name.join(' ') else null
        avatarUrl: user.avatarUrl()
        url: user.url()
      for own k, v of d
        # only update the display name if it is not set
        if k is 'name'
          robotUser[k] = v if not robotUser[k] or robotUser[k] is user.id()
        else
          robotUser[k] = v if v? and v isnt robotUser[k]
    update()
    user.on 'update', update




module.exports = HubotGitter2Adapter
