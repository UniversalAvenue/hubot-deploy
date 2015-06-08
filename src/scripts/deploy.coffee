# Description
#   Cut GitHub deployments from chat that deploy via hooks - https://github.com/atmos/hubot-deploy
#
# Commands:
#   hubot where can I deploy <app> - see what environments you can deploy app
#   hubot deploy:version - show the script version and node/environment info
#   hubot deploy <app>/<branch> to <env>/<roles> - deploys <app>'s <branch> to the <env> environment's <roles> servers
#   hubot deploys <app>/<branch> in <env> - Displays recent deployments for <app>'s <branch> in the <env> environment
#
supported_tasks = [ DeployPrefix ]

Path          = require("path")
Version       = require(Path.join(__dirname, "..", "version")).Version
Patterns      = require(Path.join(__dirname, "..", "patterns"))
Deployment    = require(Path.join(__dirname, "..", "deployment")).Deployment
Formatters    = require(Path.join(__dirname, "..", "formatters"))

DeployPrefix   = Patterns.DeployPrefix
DeployPattern  = Patterns.DeployPattern
DeploysPattern = Patterns.DeploysPattern

###########################################################################
module.exports = (robot) ->
  ###########################################################################
  # where can i deploy <app>
  #
  # Displays the available environments for an application
  robot.respond ///where\s+can\s+i\s+#{DeployPrefix}\s+([-_\.0-9a-z]+)///i, (msg) ->
    name = msg.match[1]

    try
      deployment = new Deployment(name)
      formatter  = new Formatters.WhereFormatter(deployment)

      msg.send formatter.message()
    catch err
      console.log err

  ###########################################################################
  # deploys <app> in <env>
  #
  # Displays the available environments for an application
  robot.respond DeploysPattern, (msg) ->
    name        = msg.match[2]
    environment = msg.match[4] || 'production'

    try
      deployment = new Deployment(name, null, null, environment)
      deployment.latest (deployments) ->
        formatter = new Formatters.LatestFormatter(deployment, deployments)
        msg.send formatter.message()

    catch err
      console.log err

  ###########################################################################
  # deploy hubot/topic-branch to staging
  #
  # Actually dispatch deployment requests to GitHub
  robot.respond DeployPattern, (msg) ->
    task  = msg.match[1].replace(DeployPrefix, "deploy")
    force = msg.match[2] == '!'
    name  = msg.match[3]
    ref   = (msg.match[4]||'master')
    env   = (msg.match[5]||'production')
    hosts = (msg.match[6]||'')

    username = msg.envelope.user.githubLogin or msg.envelope.user.name

    deployment = new Deployment(name, ref, task, env, force, hosts)

    reservations = robot.brain.get('reservations') || {}
    reservations[name] ||= {}
    if reservations[name][env] && reservations[name][env] != msg.envelope.user.name
      msg.reply "Sorry I can't do that, right now only #{reservations[name][env]} can deploy here."
      return

    unless deployment.isValidApp()
      msg.reply "#{name}? Never heard of it."
      return
    unless deployment.isValidEnv()
      msg.reply "#{name} doesn't seem to have an #{env} environment."
      return
    unless deployment.isAllowedRoom(msg.message.user.room)
      msg.reply "#{name} is not allowed to be deployed from this room."
      return

    user = robot.brain.userForId msg.envelope.user.id
    if user? and user.githubDeployToken?
      deployment.setUserToken(user.githubDeployToken)

    deployment.user = username
    deployment.room = msg.message.user.room

    if robot.adapterName == 'flowdock'
      deployment.message_thread = msg.message.user.message || msg.message.user.thread_id

    deployment.adapter = robot.adapterName

    console.log JSON.stringify(deployment.requestBody())

    deployment.post (responseMessage) ->
      msg.reply responseMessage if responseMessage?

  ###########################################################################
  # reserve/lock <app> <env>(defaults to staging) for <user>(slack name, me for the current user, defaults to me)
  #
  # Lets only the specified user deploy to that app/env
  robot.respond Patterns.ReservePattern, (msg) ->
    app = msg.match[1]
    env = (msg.match[2] || 'staging')
    user = (msg.match[3] || 'me')
    username = user
    if user == 'me'
      username = msg.envelope.user.name

    reservations = robot.brain.get('reservations') || {}
    reservations[app] ||= {}

    if reservations[app][env]
      if reservations[app][env] == username
        if user == 'me'
          msg.reply "You already reserved #{app} #{env}, do you really believe my brain could forget that?"
        else
          msg.reply "#{app} #{env} is already reserved to #{username}, do you really believe my brain could forget that?"
      else
        msg.send "I'm sorry but #{app} #{env} is already reserved for #{reservations[app][env]}."

    else
      reservations[app][env] = username
      robot.brain.set('reservations', reservations)
      msg.send "I will prevent everybody else from deploying to #{app} #{env} which means that probably people will blame me if #{if user == 'me' then 'you' else username} will break something."


  ###########################################################################
  # free/unlock <app> <env>(defaults to staging)
  #
  # Removes any dpeloyment reservations
  robot.respond Patterns.FreePattern, (msg) ->
    app = msg.match[1]
    env = (msg.match[2] || 'staging')

    reservations = robot.brain.get('reservations') || {}
    reservations[app] ||= {}
    delete reservations[app][env]
    robot.brain.set('reservations', reservations)
    msg.send "#{app} #{env} is now again free for deploys from everybody - I'm sure you will brake it."


  ###########################################################################
  # deploy:version
  #
  # Useful for debugging
  robot.respond ///#{DeployPrefix}\:version$///i, (msg) ->
    msg.send "hubot-deploy v#{Version}/hubot v#{robot.version}/node #{process.version}"
