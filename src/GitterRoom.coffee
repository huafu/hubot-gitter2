GitterObject = require './GitterObject'
GitterUser   = -> require './GitterUser'

# Gitter Room manipulations
class GitterRoom extends GitterObject

  # @property {Number} The maximum message size
  @MAX_MESSAGE_SIZE = 1024

  # @property {Boolean} Whether the session user joined that room or not
  _hasJoined: null

  # Creates a new room
  #
  # @param {GitterClient} client The client to be used
  # @param {Object} data The room's data
  constructor: ->
    super
    @_hasJoined = no
    # finish initialization
    @_created()

  # Did we join the room yet?
  #
  # @return {Boolean} Whether we joined the room or not
  hasJoined: ->
    @_hasJoined

  # Whether the room is a one-to-one room
  #
  # @return {Boolean} Returns true if the room is a one-to-one, else false
  isOneToOne: ->
    Boolean(@_data.oneToOne)

  # Finds whether we are listening for events on the room's resource
  # Can be used to start/stop listening for events on that room too
  #
  # @param {Boolean} listen If given, will start/stop listening depending on the value
  # @return {Boolean} Returns true if listening, else false
  isListening: (listen) ->
    if arguments.length is 1
      if listen
        self = @
        faye = @_data.streaming()
        for own resource, emitter of faye.emitters
          faye[resource]()
          # be sure we handle wildcards on event emitters
          emitter.wildcard = yes
          emitter._conf ?= {}
          emitter._conf.wildcard = yes
          emitter.listenerTree ?= {}
          # then listen for events
          @log "listening events on resource `#{ resource }`"
          ((name, em) ->
            em.on '*', -> self.emit "#{ name }.#{ @event }", arguments...
          )(resource, emitter)
      else if @_data._fayeClient
        @log "stop listening events on all resources"
        # disconnecting will stop listening all events
        @_data._fayeClient.disconnect()
        @_data._fayeClient = null
    Boolean(@_data._fayeClient)

  # Get the room's URI
  #
  # @return {String} The room's URI
  uri: ->
    @_data.uri

  # Load all users of the room
  #
  # @param {Function} callback The method to call once all users have ben loaded
  asyncUsers: (callback = ->) ->
    @_ensureClientReady()
    @_promise("users.all", => @_data.users())
    .then (users) =>
      @log "loaded #{ users.length } member users"
      parsedUsers = []
      cl = @client()
      ccl = cl.client()
      for user in users
        u = GitterUser().factory cl, ccl.users.extend(user)
        parsedUsers.push u
      callback null, parsedUsers
      return
    .fail (error) =>
      @log 'error', "error while loading member users: #{ error }"
      callback error
      return

  # Leave the room, if joined
  #
  # @param {Function} callback Method to call when left
  asyncLeave: (callback = ->) ->
    @_ensureClientReady()
    if @hasJoined()
      cl = @client()
      user = cl.sessionUser()
      @_promise("leave:#{ user }", => cl.client().removeUser user.id(), @id())
      .then =>
        @log "successfully left room #{ @ }"
        @_flagJoined no
        callback null, yes
        return
      .fail (error) =>
        @log "error while leaving room #{ @ }: #{ error }"
        callback error
        return
    else
      callback null, yes

  # Join the room if not yet joined
  #
  # @param {Function} callback Method to call when joined
  asyncJoin: (callback = ->) ->
    @_ensureClientReady()
    if @hasJoined()
      callback null, yes
    else
      @client().asyncJoinRoom @uri(), callback

  # Send a message to that room as the connected user
  #
  # @param {Array<String>, String} lines All the lines to send
  # @param {Function} callback Method to call when done
  asyncSend: (lines..., callback = ->) ->
    @_ensureClientReady()
    if typeof(callback) isnt 'function'
      lines.push callback
      callback = ->
    if lines.length is 1 and typeof(lines[0]) is 'array' or lines[0] instanceof Array
      lines = lines[0]
    # make sure not line is empty
    strings = lines.slice()
    lines = []
    for line in strings
      if line is undefined or line is null or line is ''
        lines.push ' '
      else
        lines.push "#{ line }"
    # keep track of how many messages has been asked to send
    realTotal = lines.length
    # we need to join lines without going over the max message size
    chunks = []
    while lines.length
      chunk = []
      size = 0
      while lines.length
        # here we check if we have at least one line in the chunk else we'll loop infinitely
        ls = lines[0].length + 1
        break if chunk.length > 0 and size + ls >= GitterRoom.MAX_MESSAGE_SIZE
        chunk.push lines.shift()
        size += ls
      # we create a new chunk with all possible lines that we could join
      chunks.push chunk.join('\n')
    # now we have optimized the # of messages
    lines = chunks.slice()
    if lines.length isnt realTotal
      @log "compressed #{ realTotal } lines into #{ lines.length } chunk(s)"
    # now we can send all lines
    if lines.length < 1
      # make sure we are not sending an empty message
      @log 'warning', "not sending an empty message"
      callback null, lines
    else
      # send all lines, one by one
      total = lines.length
      sent = []
      @log "sending #{ total } message chunk(s)"
      # this closure is responsible of sending one line and handling possible error of previous line
      next = ((err, lineSent) =>
        sent.push lineSent if lineSent?
        if err
          still = " (#{ lines.length + 1 } of #{ total } chunk(s) not sent)"
          @log 'error', "error sending a message#{ still }: #{ err }"
          callback err, sent
        else if (line = lines.shift())
          @_data.send(line).then(-> next(null, line)).fail(next)
        else
          @log "message of #{ total } chunk(s) sent"
          callback null, sent
        # be sure to not return nothing
        return
      )
      next()

  # Get a pretty identifier that can identify the object
  #
  # @return {String} A text identifying the object
  prettyIdentifier: ->
    @uri()

  # Internally used to flag the room as joined or not
  #
  # @param {Boolean} joined Whether it is known as joined or left
  _flagJoined: (joined) ->
    if Boolean(@_hasJoined) isnt (status = Boolean joined)
      @_hasJoined = status
      setTimeout (=> @emit if status then 'status:join' else 'status:leave'), 1



module.exports = GitterRoom
