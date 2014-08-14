
HubotGitter2Adapter = require './src/HubotGitter2Adapter'

exports.use = (robot) -> new HubotGitter2Adapter(robot)
