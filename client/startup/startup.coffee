Meteor.startup ->
	TimeSync.loggingEnabled = false

	UserPresence.awayTime = 300000
	UserPresence.start()
	Meteor.subscribe("activeUsers")

	Session.setDefault('AvatarRandom', 0)

  # start custom logic

	window.pymChild = new pym.Child({ id: 'chatapp-iframe-container'})

	pymChild.onMessage 'loginUser', (user) ->
	  user = JSON.parse(user)
	  localStorage.setItem('Meteor.loginToken', user.authToken)
	  localStorage.setItem('Meteor.loginTokenExpires', moment().add(1, 'months'))
	  localStorage.setItem('Meteor.userId', user._id)
	  document.cookie = 'meteor_login_token=' + user.authToken
	  document.cookie = 'rc_token=' + user.authToken
	  document.cookie = 'rc_uid=' + user._id

	Tracker.autorun ->
    if Meteor.userId()
      pymChild.sendMessage('childLoggedIn', 'login ready')

      subscriptions = ChatSubscription.find({open: true}, { fields: { unread: 1, alert: 1, rid: 1, t: 1, name: 1, ls: 1 } })
      for subscription in subscriptions.fetch()
        pymChild.sendMessage('unread', JSON.stringify(subscription))

      pymChild.sendMessage('unread_ready', 'ready')

	pymChild.onMessage 'loadRoom', (name) ->
    username = Meteor.user()?.username
    unless username
      return

    query =
				t: 'd'
				usernames: $all: [name, username]

    room = ChatRoom.findOne(query)
    if not room?
      Meteor.call 'createDirectMessage', name, (err) ->
        if !err
          FlowRouter.go 'private', {username: name}
    else
      FlowRouter.go 'private', {username: name}

	pymChild.sendMessage('childLoaded', 'ready')

  # end custom logic

	window.lastMessageWindow = {}
	window.lastMessageWindowHistory = {}

	@defaultAppLanguage = ->
		lng = window.navigator.userLanguage || window.navigator.language || 'en'
		# Fix browsers having all-lowercase language settings eg. pt-br, en-us
		re = /([a-z]{2}-)([a-z]{2})/
		if re.test lng
			lng = lng.replace re, (match, parts...) -> return parts[0] + parts[1].toUpperCase()
		return lng

	@defaultUserLanguage = ->
		return RocketChat.settings.get('Language') || defaultAppLanguage()

	loadedLanguages = []

	@setLanguage = (language) ->
		if !language
			return

		if loadedLanguages.indexOf(language) > -1
			return

		loadedLanguages.push language

		if isRtl language
			$('html').addClass "rtl"
		else
			$('html').removeClass "rtl"

		language = language.split('-').shift()
		TAPi18n.setLanguage(language)

		language = language.toLowerCase()
		if language isnt 'en'
			Meteor.call 'loadLocale', language, (err, localeFn) ->
				Function(localeFn)()
				moment.locale(language)

	Meteor.subscribe("userData", () ->
		userLanguage = Meteor.user()?.language
		userLanguage ?= defaultUserLanguage()

		if localStorage.getItem('userLanguage') isnt userLanguage
			localStorage.setItem('userLanguage', userLanguage)

		setLanguage userLanguage
	)
