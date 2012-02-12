# This little tester writes lines to a file every time you hit Enter.

readline = require 'readline'
fs = require 'fs'

appendSync = (filename, str) ->
  try
    len = fs.statSync(filename).size
  catch err
    # Assume nonexistent. Create:
    fs.writeFileSync filename, ''  
    len = 0  
  fd = fs.openSync(filename, 'a')
  fs.writeSync(fd, str, len)
  fs.closeSync(fd)

wrap = (func) ->
  try
    return func() ? true
  catch error
    if error.code?
      console.log error.code
    else
      console.log error
    return null
    

filename = 'test.test'

console.log "Writing to `#{ filename }`. Hit <Enter> to write another line. ^C to quit."

rl = readline.createInterface process.stdin, process.stdout, null
rl.setPrompt '> '
rl.prompt()

files_to_delete = []

files_to_delete.push filename

linenum = 0

rl.on 'close', ->
  fs.unlink filename for filename in files_to_delete
  rl.close()
  process.stdin.destroy()

rl.on 'line', (cmd) ->
  switch cmd
    when 'stat'
      wrap -> console.log fs.statSync filename
    when 'unlink'
      wrap -> fs.unlinkSync filename
    when 'rename'
      copy_name = filename+linenum
      retval = wrap -> fs.renameSync filename, copy_name
      if retval
        files_to_delete.push copy_name
        console.log "renamed to #{copy_name}; continuing to modify #{filename}"
    when 'truncate'
      fd = fs.openSync filename, 'w'
      fs.truncateSync fd
      fs.closeSync fd
      stats = fs.statSync filename
      console.log "truncated; inode=#{stats.ino}"
    else
      linetext = ('0000000000' + linenum).slice(-10)
      appendSync filename, linetext+'\n'
      console.log linetext
      linenum++
  rl.prompt()
