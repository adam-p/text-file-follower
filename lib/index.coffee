events = require('events')
util = require('util')
fs = require('fs')
watchit = require('watchit')
_ = require('underscore')


###
Figure out if the text uses \n (unix) or \r\n (windows) newlines.
###
deduce_newline_value = (sample) ->
  if sample.indexOf('\r\n') >= 0
    return '\r\n'
  return '\n'

###
Splits the text into complete lines (must end with newline). 
Returns a tuple of [bytes_consumed, [line1, line2, ...]]
###
get_lines = (text) ->
  newline = deduce_newline_value(text)
  lines = text.split(newline)
  # Exclude the last item in the array, since it will be an empty or incomplete line.
  lines.pop()

  if lines.length == 0
    return [0, []]

  bytes_consumed = _.reduce(lines, 
                            (memo, line) -> return memo+line.length,
                            0)
  # Add back the newline characters
  bytes_consumed += lines.length * newline.length

  return [bytes_consumed, lines]


###
The emitter that's returned from follow(). It can be used to listen for events,
and it can also be used to close the follower.
###
class Follower extends events.EventEmitter
  constructor: (@watcher) ->
  
  # Shut down the follower
  close: -> 
    @watcher.close()


default_options = 
  persistent: true

###
Watch for changes on `filename`.
`options` is an optional object that looks like the following:
  {
    persistent: boolean, (default: true; ref: http://nodejs.org/docs/latest/api/fs.html#fs.watch)
  }
listener is an optional callback that takes two arguments: `(event, value)`. The 
possible event is `line`, and the value will the new line that has been added to 
the watched/followed file. 
Returns an instance of the Follower object, which is an EventEmitter and can be 
used to listen for the `line` and `error` events. It also has a `close()` member 
that ends the following. Emitted events pass the watched filename (and the line,
for `line` to the bound callback).
###

follow = (filename, options = {}, listener = null) ->

  # Check arguments and sort out the optional ones.

  if not listener? and typeof(options) == 'function'
    listener = options
    options = {}

  if typeof(filename) != 'string'
    throw TypeError('`filename` must be a string')

  if typeof(options) != 'object'
    throw TypeError('if supplied, `options` must be an object')

  if listener? and typeof(listener) != 'function'
    throw TypeError('if supplied, `listener` must be a function')

  # Fill in options defaults
  options = _.defaults(options, default_options)

  stats = fs.statSync(filename)

  if not stats.isFile()
    throw new Error("#{ filename } is not a file")

  prev_size = stats.size
  prev_mtime = stats.mtime

  # Set up the file watcher
  watcher = watchit(filename, { debounce: false, retain: true, persistent: options.persistent })

  # If the file gets newly re-created (e.g., after a log rotate), then we want
  # to start watching it from the beginning.
  watcher.on('create', -> prev_size = 0)
  watcher.on('unlink', -> prev_size = 0)

  # Create the Follower object that we'll ultimately return
  follower = new Follower(watcher)
  if listener? then follower.addListener('line', listener)

  watcher.on 'success', -> 
    follower.emit('success', filename)

  watcher.on('failure', -> 
    follower.emit('error', filename))

  # Function that gets called when a change is detected in the file.
  onchange = (filename) -> 

    # Get the new filesize and abort if it hasn't grown or gotten newer
    stats = fs.statSync(filename)

    if stats.size <= prev_size then return

    # Aborting if the mtime is the same is a pretty ham-fisted way of dealing
    # with duplicate notifications. We'll disable it for now.
    #if stats.mtime.getTime() == prev_mtime.getTime() then return

    prev_mtime = stats.mtime

    # Not every chunk of data we get will have complete lines, so we'll often
    # have to keep a piece of the previous chunk to process the next.
    accumulated_data = ''

    read_stream = fs.createReadStream(filename, { encoding: 'utf8', start: prev_size })
    read_stream.on 'data', (new_data) -> 
      accumulated_data += new_data
      [bytes_consumed, lines] = get_lines(accumulated_data)

      # Move our data forward by the number of bytes we've really processed.
      accumulated_data = accumulated_data[bytes_consumed..]
      prev_size += bytes_consumed

      # Tell our listeners about the new lines
      lines.forEach((line) -> follower.emit('line', filename, line))

  # Hook up our change handler to the file watcher
  watcher.on('change', onchange)

  return follower


exports.follow = follow
  
# debug
exports.__get_debug_exports = ->
    deduce_newline_value: deduce_newline_value
    get_lines: get_lines
