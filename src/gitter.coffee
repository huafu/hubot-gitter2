
HubotGitter2Adapter = require './HubotGitter2Adapter'

exports.use = (robot) -> new HubotGitter2Adapter(robot)
