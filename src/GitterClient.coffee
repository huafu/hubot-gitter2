Gitter       = require 'node-gitter'
GitterObject = require './GitterObject'
GitterRoom   = -> require './GitterRoom'
GitterUser   = -> require './GitterUser'

class GitterClient extends GitterObject

  # @property {GitterUser} The logged in user
  _sessionUser: null

  # @property {Boolean} Whether the client is ready or not
  _isReady: null

  # @property {Boolean} Whether we are loading the session user to get ready
  _isGettingReady: null

  # Create a new instance of a client or grab the existing one thanks to the token
  #
  # @option data {String} token The user token to connect to the server
  # @return {GitterClient} The created or existing client object
  @factory: (data) ->
    data.id = data.token unless data.id
    data.token = data.id unless data.token
    GitterObject.factory.apply @, [null, data]

  # Creates a new instance of the client and try to connect
  #
  # @param {null} dummy Not used
  # @param {Object} data The client's data
  constructor: ->
    @_isReady = no
    @_isGettingReady = no
    start = new Date()
    super
    @_client = new Gitter(@token())
    for k, v of @_client.client when typeof(v) is "function"
      @_client.client[k] = ((name, original) =>
        @log "overriding {client##{ name }}"
        =>
          @log "{client##{ name }} [#{ Array::join.call arguments, ', ' }]"
          original.apply @_client.client, arguments
      )(k, v)
    @_isGettingReady = yes
    @_asyncSessionUser (err) =>
      if err
        @log 'error', err
      else
        ms = Date.now() - start
        @log 'info', "client ready in #{ Math.round(ms * 1000) / 1000 } milliseconds"
        @_isReady = yes
        @emit 'ready', ms
    # finish initialization
    @_created()

  # Get the session's user
  #
  # @return {GitterUser} The session user
  sessionUser: ->
    @_ensureClientReady()
    @_sessionUser

  # Get the client's token
  #
  # @return {String} The client's token
  token: ->
    @_data.token

  # Finds whether the client is ready or not
  #
  # @return {Boolean} Returns true if the client is ready, else false
  isReady: ->
    @_isReady

  # Join a room using its URI
  #
  # @param {String} uri The room to join
  # @param {Function} callback The method to call once the room has been joined
  asyncJoinRoom: (uri, callback = ->) ->
    @_ensureClientReady()
    @_promise("rooms.join:#{ uri }", => @client().rooms.join uri)
    .then (r) =>
      room = GitterRoom().factory @, r
      room._flagJoined yes
      @log 'info', "successfully joined room #{ room }"
      callback null, room
      return
    .fail (err) =>
      @log 'error', "error joining room `#{ uri }`: #{ err }"
      callback err
      return

  # Search a room using the first found property in options, in this order: `id`, `uri`
  # If the room URI is given and the room isn't known yet, it'll join the room
  #
  # @option options {String} id The room's id
  # @option options {String} uri The room's URI
  # @param {Function} callback The method to call once the room has been found
  asyncRoom: (options, callback = ->) ->
    @_ensureClientReady()
    if options.id
      prop = 'id'
    else if options.uri
      prop = 'uri'
    else
      throw new ReferenceError("neither `id` nor `uri` property exists on the given options `#{ options }`")
    val = options[prop]
    if (room = GitterObject.findBy @, GitterRoom(), prop, val)
      @log "found room with #{ prop } `#{ val }`: #{ room }"
      callback null, room
    else if prop is 'id'
      @_promise("rooms.find:#{ prop }:#{ val }", => @client().rooms.find(val))
      .then (r) =>
        room = GitterRoom().factory(@, r)
        @log "loaded room with #{ prop } `#{ val }`: #{ room }"
        callback null, room
        return
      .fail (error) =>
        @log 'error', "unable to find room with #{ prop } `#{ val }`: #{ error }"
        callback error
        return
    else
      @asyncJoinRoom val, callback

  # Search a user using the first found property in options, in this order: `id`, `login`
  # If the user login is given and the user isn't known yet, it'll fail finding the user
  #
  # @option options {String} id The user's id
  # @option options {String} login The user's login
  # @param {Function} callback The method to call once the user has been found
  asyncUser: (options, callback = ->) ->
    @_ensureClientReady()
    if options.id
      prop = 'id'
    else if options.login
      prop = 'login'
    else
      throw new ReferenceError("neither `id` nor `login` property exists on the given options `#{ options }`")
    val = options[prop]
    if (user = GitterObject.findBy @, GitterUser(), prop, val)
      @log "found user with #{ prop } `#{ val }`: #{ user }"
      callback null, user
    else if prop is 'id'
      @_promise("users.find:#{ prop }:#{ val }", => @client().users.find(val))
      .then (u) =>
        user = GitterUser().factory(@, u)
        @log "loaded user with #{ prop } `#{ val }`: #{ user }"
        callback null, user
        return
      .fail (error) =>
        @log 'error', "unable to find user with #{ prop } `#{ val }`: #{ error }"
        callback error
        return
    else
      @log 'error', msg = "the user with #{ prop } `#{ val }` is unknown"
      callback new Error(msg)

  # Load all known rooms
  #
  # @param {Function} callback The function to call when loaded
  asyncRooms: (callback = ->) ->
    @_ensureClientReady()
    @_promise("rooms.all", => @client().rooms.findAll())
    .then (rooms) =>
      @log "loaded #{ rooms.length } rooms"
      parsedRooms = []
      cl = @client()
      for r in rooms
        room = GitterRoom().factory @, cl.rooms.extend(r)
        room._flagJoined yes
        parsedRooms.push room
      callback null, parsedRooms
      return
    .fail (error) =>
      @log 'error', "error while loading all rooms: #{ error }"
      callback error
      return

  # Loads the session user (logged-in user)
  #
  # @param {Function} callback The function to call when loaded
  _asyncSessionUser: (callback = ->) ->
    if @_isGettingReady
      @_isGettingReady = no
    else
      @_ensureClientReady()
    if @_sessionUser
      callback null, @_sessionUser
    else
      @_promise("users.current", => @client().currentUser())
      .then (user) =>
        @_sessionUser = GitterUser().factory(@, user)
        @log 'info', "loaded session user: #{ @_sessionUser }"
        callback null, @_sessionUser
        return
      .fail (error) =>
        @log 'error', "error while loading session user: #{ error }"
        callback error
        return


module.exports = GitterClient
