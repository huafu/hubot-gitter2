

GitterObject = require './GitterObject'
GitterUser = require './GitterUser'

# Gitter Room manipulations
class GitterRoom extends GitterObject

  # @property {Boolean} Whether the session user joined that room or not
  _hasJoined: null

  # Creates a new room and take care of loading its users
  #
  # @param {GitterClient} client The client to be used
  # @param {Object} data The room's data
  constructor: ->
    super
    @_hasJoined = no

  # Did we join the room yet?
  #
  # @return {Boolean} Whether we joined the room or not
  hasJoined: ->
    @_hasJoined

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
            em.on '*', -> self.emit "#{ name }:event", @event, arguments...
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
    @_promise("users.all", => @_data.users())
    .then (users) =>
      @log "loaded #{ users.length } member users"
      parsedUsers = []
      cl = @client()
      ccl = cl.client()
      for user in users
        u = GitterUser.factory cl, ccl.users.extend(user)
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
    if @hasJoined()
      cl = @client()
      cl.asyncSessionUser (error, user) =>
        if error
          callback error
        else
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
    if @hasJoined()
      callback null, yes
    else
      @client().asyncJoinRoom @uri(), callback

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
