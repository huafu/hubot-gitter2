GitterObject = require './GitterObject'
GitterRoom = require './GitterRoom'

# Handle a Gitter user
class GitterUser extends GitterObject

  # Get the login/user name of the user
  #
  # @return {String} User name
  login: ->
    @_data.username

  # Get the display name of the user
  #
  # @return {String} Display name of the user
  displayName: ->
    @_data.displayName

  # Get the avatar URL of the user
  #
  # @return {String} Avatar URL of the user
  avatarUrl: ->
    @_data.avatarUrlMedium

  # Get the URL of the user
  #
  # @param {Boolean} full If true, the full URL is returned instead of just the path
  # @return {String} URL of the user's profile
  url: (full = no) ->
    if full
      "https://www.github.com#{ @_data.url }"
    else
      @_data.url

  # Load rooms in which the user is
  #
  # @param {Function} callback The method to call once the room list is there
  asyncRooms: (callback = ->) ->
    @_promise("rooms.all", => @_data.rooms())
    .then (rooms) =>
      @log "loaded #{ rooms.length } rooms which user is a member of"
      parsedRooms = []
      cl = @client()
      ccl = cl.client()
      for r in rooms
        room = GitterRoom.factory cl, ccl.rooms.extend(r)
        room._flagJoined yes
        parsedRooms.push room
      callback null, parsedRooms
      return
    .fail (error) =>
      @log 'error', "error loading rooms the user is a member of: #{ error }"
      callback error
      return

  # Join all rooms in which the user is and has not yet joined


  # Get a pretty identifier that can identify the object
  #
  # @return {String} A text identifying the object
  prettyIdentifier: ->
    @login()




module.exports = GitterUser
