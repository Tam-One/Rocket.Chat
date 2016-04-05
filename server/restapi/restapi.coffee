Api = new Restivus
  useDefaultAuth: true
  prettyJson: true
  enableCors: false


Api.addRoute 'info', authRequired: false,
  get: -> RocketChat.Info


Api.addRoute 'version', authRequired: false,
  get: ->
    version = {api: '0.1', rocketchat: '0.5'}
    status: 'success', versions: version

Api.addRoute 'publicRooms', authRequired: true,
  get: ->
    rooms = RocketChat.models.Rooms.findByType('c', { sort: { msgs:-1 } }).fetch()
    status: 'success', rooms: rooms


# custom Api routes


# find private rooms by username
Api.addRoute 'rooms/find/direct/:username', authRequired: true,
  get: ->
    Meteor.runAsUser this.userId, () =>
    rooms = RocketChat.models.Rooms.findByTypeContainigUsername('d', @urlParams.username).fetch()
    status: 'success', rooms: rooms


# create a DirectMessage room
Api.addRoute 'rooms/create/direct/:username', authRequired: true,
  post: ->
    Meteor.runAsUser this.userId, () =>
      room = Meteor.call('createDirectMessage', @urlParams.username)
      status: 'success', rid: room.rid   # need to handle error


# find user by username
Api.addRoute 'users/find/:username', authRequired: true,
  get: ->
    if RocketChat.authz.hasPermission( @userId, 'view-full-other-user-info') is true
      Meteor.runAsUser this.userId, () =>
        user = RocketChat.models.Users.findOneByUsername @urlParams.username
        status: 'success', user: user || false
    else
      statusCode: 403
      body: status: 'error', message: 'You do not have permission to do this'


# find user by id
Api.addRoute 'users/get/:id', authRequired: true,
  get: ->
    if RocketChat.authz.hasPermission( @userId, 'view-full-other-user-info') is true
      Meteor.runAsUser this.userId, () =>
        user = RocketChat.models.Users.findOneById @urlParams.id
        status: 'success', user: user || false
    else
      statusCode: 403
      body: status: 'error', message: 'You do not have permission to do this'


# create user
Api.addRoute 'users/create', authRequired: true,
  post:
    action: ->
      if RocketChat.authz.hasPermission(@userId, 'add-user')
        try
          userObj = { name: @bodyParams.username, email: @bodyParams.email, pass: @bodyParams.pass }
          Api.testapiValidateUsers  [userObj]
          this.response.setTimeout (500)
          userObj.name = @bodyParams.name
          id = {uid: Meteor.call 'registerUser', userObj}
          Meteor.runAsUser id.uid, () =>
            Meteor.call 'setUsername', @bodyParams.username

          Meteor.runAsUser this.userId, () =>
            RocketChat.models.Users.setUserActive id.ui
            RocketChat.models.Users.setEmailVerified id.uid, @bodyParams.email

          user = RocketChat.models.Users.findOneById id.uid

          status: 'success', user: user
        catch e
          statusCode: 400    # bad request or other errors
          body: status: 'fail', message: e.name + ' :: ' + e.message
      else
        statusCode: 403
        body: status: 'error', message: 'You do not have permission to do this'


# update user
Api.addRoute 'users/update/:id', authRequired: true,
  post:
    action: ->
      if RocketChat.authz.hasPermission(@userId, 'add-user')
        try
          if @bodyParams.name
            RocketChat.models.Users.setName @urlParams.id, @bodyParams.name

          if @bodyParams.username
            RocketChat.setUsername @urlParams.id, @bodyParams.username

          if @bodyParams.email
            RocketChat.setEmail @urlParams.id, @bodyParams.email

          canEditUserPassword = RocketChat.authz.hasPermission( @userId, 'edit-other-user-password')
          if @bodyParams.pass and @bodyParams.pass.trim() and canEditUserPassword
            Accounts.setPassword @urlParams.id, @bodyParams.pass.trim()

          user = RocketChat.models.Users.findOneById @urlParams.id

          status: 'success', user: user
        catch e
          statusCode: 400
          body: status: 'fail', message: e.name + ' :: ' + e.message
      else
        statusCode: 403
        body: status: 'error', message: 'You do not have permission to do this'


# delete user
Api.addRoute 'users/delete/:id', authRequired: true,
  delete:
    action: ->
      if RocketChat.authz.hasPermission(@userId, 'delete-user')
        try
          Meteor.runAsUser this.userId, () =>
            deleted = Meteor.call 'deleteUser', @urlParams.id
            if deleted
              status: 'success'
            else
              status: 'fail', message: 'Failed to delete user'
        catch e
          statusCode: 400
          body: status: 'fail', message: e.name + ' :: ' + e.message
      else
        statusCode: 403
        body: status: 'error', message: 'You do not have permission to do this'



# end custom Api routes


# join a room
Api.addRoute 'rooms/:id/join', authRequired: true,
  post: ->
    Meteor.runAsUser this.userId, () =>
      Meteor.call('joinRoom', @urlParams.id)
    status: 'success'   # need to handle error

# leave a room
Api.addRoute 'rooms/:id/leave', authRequired: true,
  post: ->
    Meteor.runAsUser this.userId, () =>
      Meteor.call('leaveRoom', @urlParams.id)
    status: 'success'   # need to handle error


# get messages in a room
Api.addRoute 'rooms/:id/messages', authRequired: true,
  get: ->
    try
      if Meteor.call('canAccessRoom', @urlParams.id, this.userId)
        msgs = RocketChat.models.Messages.findVisibleByRoomId(@urlParams.id, {sort: {ts: -1}, limit: 50}).fetch()
        status: 'success', messages: msgs
      else
        statusCode: 403   # forbidden
        body: status: 'fail', message: 'Cannot access room.'
    catch e
      statusCode: 400    # bad request or other errors
      body: status: 'fail', message: e.name + ' :: ' + e.message



# send a message in a room -  POST body should be { "msg" : "this is my message"}
Api.addRoute 'rooms/:id/send', authRequired: true,
  post: ->
    Meteor.runAsUser this.userId, () =>
      Meteor.call('sendMessage', {msg: this.bodyParams.msg, rid: @urlParams.id} )
    status: 'success'	#need to handle error


# validate an array of users
Api.testapiValidateUsers =  (users) ->
  for user, i in users
    if user.name?
      if user.email?
        if user.pass?
          try
            nameValidation = new RegExp '^' + RocketChat.settings.get('UTF8_Names_Validation') + '$', 'i'
          catch
            nameValidation = new RegExp '^[0-9a-zA-Z-_.]+$', 'i'

          if nameValidation.test user.name
            if  /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]+\b/i.test user.email
              continue
    throw new Meteor.Error 'invalid-user-record', "[restapi] register -> record #" + i + " is invalid"
  return


###
@api {post} /bulk/register  Register multiple users based on an input array.
@apiName register
@apiGroup TestAndAdminAutomation
@apiVersion 0.0.1
@apiDescription  Caller must have 'testagent' or 'adminautomation' role.
NOTE:   remove room is NOT recommended; use Meteor.reset() to clear db and re-seed instead
@apiParam {json} rooms An array of users in the body of the POST.
@apiParamExample {json} POST Request Body example:
  {
    'users':[ {'email': 'user1@user1.com',
               'name': 'user1',
               'pass': 'abc123' },
              {'email': 'user2@user2.com',
               'name': 'user2',
               'pass': 'abc123'},
              ...
            ]
  }
@apiSuccess {json} ids An array of IDs of the registered users.
@apiSuccessExample {json} Success-Response:
  HTTP/1.1 200 OK
  {
    'ids':[ {'uid': 'uid_1'},
            {'uid': 'uid_2'},
            ...
    ]
  }
###
Api.addRoute 'bulk/register', authRequired: true,
  post:
  # restivus 0.8.4 does not support alanning:roles using groups
  #roleRequired: ['testagent', 'adminautomation']
    action: ->
      if RocketChat.authz.hasPermission(@userId, 'bulk-register-user')
        try

          Api.testapiValidateUsers  @bodyParams.users
          this.response.setTimeout (500 * @bodyParams.users.length)
          ids = []
          endCount = @bodyParams.users.length - 1
          for incoming, i in @bodyParams.users
            ids[i] = {uid: Meteor.call 'registerUser', incoming}
            Meteor.runAsUser ids[i].uid, () =>
              Meteor.call 'setUsername', incoming.name
              Meteor.call 'joinDefaultChannels'

          status: 'success', ids: ids
        catch e
          statusCode: 400    # bad request or other errors
          body: status: 'fail', message: e.name + ' :: ' + e.message
      else
        console.log '[restapi] bulk/register -> '.red, "User does not have 'bulk-register-user' permission"
        statusCode: 403
        body: status: 'error', message: 'You do not have permission to do this'




# validate an array of rooms
Api.testapiValidateRooms =  (rooms) ->
  for room, i in rooms
    if room.name?
      if room.members?
        if room.members.length > 1
          try
            nameValidation = new RegExp '^' + RocketChat.settings.get('UTF8_Names_Validation') + '$', 'i'
          catch
            nameValidation = new RegExp '^[0-9a-zA-Z-_.]+$', 'i'

          if nameValidation.test room.name
            continue
    throw new Meteor.Error 'invalid-room-record', "[restapi] bulk/createRoom -> record #" + i + " is invalid"
  return


###
@api {post} /bulk/createRoom Create multiple rooms based on an input array.
@apiName createRoom
@apiGroup TestAndAdminAutomation
@apiVersion 0.0.1
@apiParam {json} rooms An array of rooms in the body of the POST. 'name' is room name, 'members' is array of usernames
@apiParamExample {json} POST Request Body example:
  {
    'rooms':[ {'name': 'room1',
               'members': ['user1', 'user2']
  	      },
  	      {'name': 'room2',
               'members': ['user1', 'user2', 'user3']
              }
              ...
            ]
  }
@apiDescription  Caller must have 'testagent' or 'adminautomation' role.
NOTE:   remove room is NOT recommended; use Meteor.reset() to clear db and re-seed instead

@apiSuccess {json} ids An array of ids of the rooms created.
@apiSuccessExample {json} Success-Response:
  HTTP/1.1 200 OK
  {
    'ids':[ {'rid': 'rid_1'},
            {'rid': 'rid_2'},
            ...
    ]
  }
###
Api.addRoute 'bulk/createRoom', authRequired: true,
  post:
  # restivus 0.8.4 does not support alanning:roles using groups
  #roleRequired: ['testagent', 'adminautomation']
    action: ->
      # user must also have create-c permission because
      # createChannel method requires it
      if RocketChat.authz.hasPermission(@userId, 'bulk-create-c')
        try
          this.response.setTimeout (1000 * @bodyParams.rooms.length)
          Api.testapiValidateRooms @bodyParams.rooms
          ids = []
          Meteor.runAsUser this.userId, () =>
            (ids[i] = Meteor.call 'createChannel', incoming.name, incoming.members) for incoming,i in @bodyParams.rooms
          status: 'success', ids: ids   # need to handle error
        catch e
          statusCode: 400    # bad request or other errors
          body: status: 'fail', message: e.name + ' :: ' + e.message
      else
        console.log '[restapi] bulk/createRoom -> '.red, "User does not have 'bulk-create-c' permission"
        statusCode: 403
        body: status: 'error', message: 'You do not have permission to do this'



