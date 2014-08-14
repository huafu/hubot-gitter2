Gitter       = require 'node-gitter'
GitterObject = require './GitterObject'
GitterRoom   = require './GitterRoom'
GitterUser   = require './GitterUser'

class GitterClient extends GitterObject

  # @property {GitterUser} The logged in user
  _sessionUser: null

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
    super
    @_client = new Gitter(@token())
    for k, v of @_client.client when typeof(v) is "function"
      @_client.client[k] = ((name, original) =>
        @log "overriding {client##{ name }}"
        =>
          @log "{client##{ name }} [#{ Array::join.call arguments, ', ' }]"
          original.apply @_client.client, arguments
      )(k, v)

  # Get the client's token
  #
  # @return {String} The client's token
  token: ->
    @_data.token

  # Join a room using its URI
  #
  # @param {String} uri The room to join
  # @param {Function} callback The method to call once the room has been joined
  asyncJoinRoom: (uri, callback = ->) ->
    @_promise("rooms.join:#{ uri }", => @client().rooms.join uri)
    .then (r) =>
      room = GitterRoom.factory @, r
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
    if options.id
      prop = 'id'
    else if options.uri
      prop = 'uri'
    else
      throw new ReferenceError("neither `id` nor `uri` property exists on the given options `#{ options }`")
    val = options[prop]
    if (room = GitterObject.findBy @, GitterRoom, prop, val)
      @log "found room with #{ prop } `#{ val }`: #{ room }"
      callback null, room
    else if prop is 'id'
      @_promise("rooms.find:#{ prop }:#{ val }", => @client().rooms.find(val))
      .then (r) =>
        room = GitterRoom.factory(@, r)
        @log "loaded room with #{ prop } `#{ val }`: #{ room }"
        callback null, room
        return
      .fail (error) =>
        @log 'error', "unable to find room with #{ prop } `#{ val }`: #{ error }"
        return
    else
      @asyncJoinRoom val, callback

  # Load all known rooms
  #
  # @param {Function} callback The function to call when loaded
  asyncRooms: (callback = ->) ->
    @_promise("rooms.all", => @client().rooms.findAll())
    .then (rooms) =>
      @log "loaded #{ rooms.length } rooms"
      parsedRooms = []
      cl = @client()
      for r in rooms
        room = GitterRoom.factory @, cl.rooms.extend(r)
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
  asyncSessionUser: (callback = ->) ->
    if @_sessionUser
      callback null, @_sessionUser
    else
      @_promise("users.current", => @client().currentUser())
      .then (user) =>
        @_sessionUser = GitterUser.factory(@, user)
        @log 'info', "loaded session user: #{ @_sessionUser }"
        callback null, @_sessionUser
        return
      .fail (error) =>
        @log 'error', "error while loading session user: #{ error }"
        callback error
        return


module.exports = GitterClient
