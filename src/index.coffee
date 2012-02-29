###
Copyright (c) 2012 Adam Pritchard <pritchard.adam@gmail.com>

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
###

events = require('events')
util = require('util')
fs = require('fs')
watchit = require('watchit')
_ = require('underscore')



default_options =
  persistent: true
  catchup: false

###
Watch for changes on `filename`.
`options` is an optional object that looks like the following:
  {
    persistent: boolean, (default: true; ref: http://nodejs.org/docs/latest/api/fs.html#fs.watch)
    catchup: boolean, (default: false; if true, file will be processed from start)
  }

`listener` is an optional callback that takes three arguments: `(event, filename, value)`.
(See the 'all' event description below for the meaning of the arguments.)

The follow function returns an instance of the Follower object, which is an EventEmitter.

If a specific event is listened for, the callback will be passed `(filename, value)`.
The `'all'` event can also be listened for. Its callback will be passed
`(event, filename, value)` (exactly like the listener callback passed into `follow`).

The possible events are:
  * `'success'`: The follower started up successfully. Will be delayed if file
                 does not exist. `value` is undefined.
  * `'line'`: `value` will be the new line that has been added to the file.
  * `'close'`: The follower has been closed. `value` is undefined.
  * `'error'`: An error has occurred. `value` will contain error information.

The returned emitter also has a `close()` member that stops and closes the follower.
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

  # Set up the file watcher
  watcher = watchit(filename, { debounce: false, retain: true, persistent: options.persistent })

  # Create the Follower object that we'll ultimately return
  follower = new Follower(watcher, filename)

  # Create the LineReader object that we'll use for reading lines
  lineReader = new LineReader(follower)

  if listener? then follower.addListener('all', listener)

  prev_size = 0
  prev_mtime = null

  # If the file gets newly re-created (e.g., after a log rotate), then we want
  # to start watching it from the beginning.
  watcher.on('create', -> prev_size = 0)
  watcher.on('unlink', -> prev_size = 0)

  # watchit will emit success every time the file is unlinked and recreated, but
  # we only want to emit it once.
  success_emitted = false
  watcher.on 'success', ->
    if not success_emitted then follower.emit('success')
    success_emitted = true

  watcher.on 'failure', ->
    follower.emit('error', 'watchit failure')

  watcher.on 'close', ->
    # It doesn't feel right to me that watchit emits the 'close' event synchronously
    # with close() being called. It means that code that looks like this doesn't
    # work (and I think it should):
    #   mywatcher.close()
    #   mywatcher.on('close', -> do something)
    # I'm not certain my feeling is right, but I see no harm in making it behave
    # this way.
    # So I'm going to make the propagation of it asynchronous:
    _.defer -> follower.emit('close')

  fs.stat filename, (error, stats) ->
    if error?
      # Just return on file-not-found
      if error.code != 'ENOENT'
        follower.emit('error', error)
      return

    if not stats.isFile()
      follower.emit('error', 'not a file')
      return

    prev_mtime = stats.mtime

    # If the `catchup` option is true, start reading from the start of the file.
    if options.catchup
      lineReader.read(prev_size, (bytes_consumed) -> prev_size += bytes_consumed)
    else
      prev_size = stats.size

  # Function that gets called when a change is detected in the file.
  onchange = (filename) ->

    # Get the new filesize and abort if it hasn't grown or gotten newer
    fs.stat filename, (error, stats) ->
      if error?
        # Just return on file-not-found
        if error.code != 'ENOENT'
          follower.emit('error', error)
        return

      if stats.size <= prev_size then return

      # Aborting if the mtime is the same is a pretty ham-fisted way of dealing
      # with duplicate notifications. We'll disable it for now.
      #if stats.mtime.getTime() == prev_mtime.getTime() then return

      prev_mtime = stats.mtime

      lineReader.read(prev_size, (bytes_consumed) -> prev_size += bytes_consumed)

  # Hook up our change handler to the file watcher
  watcher.on('change', onchange)

  return follower


###
Helpers
###

###
The emitter that's returned from follow(). It can be used to listen for events,
and it can also be used to close the follower.
###
class Follower extends events.EventEmitter
  constructor: (@watcher, @filename) ->

  # Shut down the follower
  close: ->
    if @watcher?
      @watcher.close()
    else
      _.defer -> emit 'close'

  # Override EventEmitter.emit to support the `'all'` event (and to suppress
  # `'newListener'` events). Borrowed from watchit's implmentation.
  emit: (event, etc...) ->
    return if event is 'newListener'
    super event, @filename, etc...
    super 'all', event, @filename, etc...


###
This class is used to do the reading from the watched file. It emits lines via
the `follower` constructor argument and keeps track of the number of bytes read
via the `bytes_consumed_callback` argument to `read()`.
An important function served by this class is to prevent multiple simultaneous
reads on the same file (by the same follower).
###
class LineReader
  constructor: (@follower) ->
    @_readstream = null

  # Reads lines from `@filename`, starting at `start_pos`. Emits read lines.
  # `bytes_consumed_callback` may be called multiple times -- the argument is
  # the number of bytes consumed from the file.
  # This function ensures that reading can only be started on a file if there is
  # currently no other reading taking place.
  read: (start_pos, bytes_consumed_callback) ->

    # Don't start reading a file that we're already reading.
    if @_readstream? and @_readstream.readable
      return

    # Not every chunk of data we get will have complete lines, so we'll often
    # have to keep a piece of the previous chunk to process the next.
    accumulated_data = ''

    @_readstream = fs.createReadStream(@follower.filename, { encoding: 'utf8', start: start_pos })

    @_readstream.on 'error', (error) =>
      # Swallow file-not-found; pass everything else up
      if error.code != 'ENOENT'
        @follower.emit('error', error)

    @_readstream.on 'data', (new_data) =>
      accumulated_data += new_data
      [bytes_consumed, lines] = @_get_lines(accumulated_data)

      # Move our data forward by the number of bytes we've really processed.
      accumulated_data = accumulated_data[bytes_consumed..]

      bytes_consumed_callback(bytes_consumed)

      # Tell our listeners about the new lines
      lines.forEach (line) =>
        @follower.emit('line', line)


  ###
  Figure out if the text uses \n (unix) or \r\n (windows) newlines.
  ###
  _deduce_newline_value: (sample) ->
    if sample.indexOf('\r\n') >= 0
      return '\r\n'
    return '\n'

  ###
  Splits the text into complete lines (must end with newline).
  Returns a tuple of [bytes_consumed, [line1, line2, ...]]
  ###
  _get_lines: (text) ->
    newline = @_deduce_newline_value(text)
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


# The main export is the sole real function
module.exports = follow

# Also export the helpers for debug-testing
module.exports.__get_debug_exports = ->
    LineReader: LineReader
