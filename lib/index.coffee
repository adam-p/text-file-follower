fs = require('fs')
_ = require('underscore')


###
Figure out if the text uses \n (unix) or \r\n (windows) newlines.
###
deduce_newline_value = (sample) ->
  if sample.split('\r\n').length > 1
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
  lines = _.initial(lines)

  if lines.length == 0
    return [0, []]

  bytes_consumed = _.reduce(lines, 
                            (memo, line) -> return memo+line.length,
                            0)
  # Add back the newline characters
  bytes_consumed += lines.length * newline.length

  return [bytes_consumed, lines]


###
Watch for changes on `filename`
###
follow = (filename, callback, catchup=false, options=null) ->

  stats = fs.statSync(filename)

  if not stats.isFile()
    throw new Error('`filename` is not a file')
  console.log('passed isFile test')
  prev_size = 0

  fs.stat(filename, (err, stats) ->
    if err
      throw(err)
      size = stats.size
    )

  watcher = fs.watch(filename, (event) -> 
    console.log(event))

  return stop: ->  # will call to FSWatcher.close()


exports.follow = follow
  
# debug
exports.__get_debug_exports = ->
    deduce_newline_value: deduce_newline_value
    get_lines: get_lines
