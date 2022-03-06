return {
  title = 'Light Home Automation',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'engine.json'
    },
    work = {
      title = 'The work directory',
      type = 'string',
      default = 'work'
    },
    address = {
      title = 'The binding address',
      type = 'string',
      default = '::'
    },
    port = {
      type = 'integer',
      default = 8080,
      minimum = 0,
      maximum = 65535
    },
    heartbeat = {
      type = 'number',
      default = 15,
      multipleOf = 0.1,
      minimum = 0.5,
      maximum = 3600
    },
    loglevel = {
      title = 'The log level',
      type = 'string',
      default = 'WARN',
      enum = {'ERROR', 'WARN', 'INFO', 'CONFIG', 'FINE', 'FINER', 'FINEST', 'DEBUG', 'ALL'}
    },
  },
}
