
# Text File Follower

A Node.js module for getting each new last line of a text file as it appears. Think `tail -f`. Its obvious use is for consuming log lines, but it can be used for any newline-delimited text file.

`text-file-follower` is written in CoffeeScript, but a compiled JavaScript can be found in the `lib` directory.

## Usage

Some day installation will be via `npm`. For now you'll have to put the code where you want it (either lib/index.js or src/index.coffee).

A simple usage example:

```javascript
var follow = require('text-file-follower');

var follower = follow('/var/log/syslog');

follower.on('line', function(filename, line) {
  console.log('Got a new line from '+filename+': '+line);
});

// ... and then eventually:
follower.close();
```

The follow function's arguments are:

    (filename, options = {}, listener = null)

`options` is an optional object with the following field:

    {
      persistent: boolean [default: true],
      catchup: boolean [default: false]
    }

For the meaning of `persistent`, see the [fs.watch documentation](http://nodejs.org/docs/latest/api/fs.html#fs.watch). If `catchup` is `true`, lines will be read and emitted from the beginning of the file, rather than only new lines being read and emitted.

`listener` is an optional callback that takes three arguments: `(event, filename, value)`. (See the 'all' event description below for the meaning of the arguments.)

The follow function returns an instance of the `Follower` object, which is an EventEmitter.

If a specific event is listened for, the callback will be passed `(filename, value)`. The ``'all'`` event can also be listened for -- its callback will be passed `(event, filename, value)` (exactly like the listener callback passed into `follow`).

The returned emitter also has a `close()` member that stops and closes the follower.

### Events

The possible events are:

  * `'success'`: The follower started up successfully. Will be delayed if file does not exist. `value` is undefined.
  * `'line'`: `value` will be the new line that has been added to the file.
  * `'close'`: The follower has been closed. `value` is undefined.
  * `'error'`: An error has occurred. `value` will contain error information.
  * `'all'`: Not a real event, but a catch-all for the others. See above.

### Running the tests

    > make test

### More examples

```javascript
var follow = require('text-file-follower');

var allEventsCallback = function(event, filename, value) {
  switch (event) {
    case 'success':
      console.log("Got success -- file exists and we're following");
      break;
    case 'line':
      console.log("A line was appended to the file: " + value);
      break;
    case 'close':
      console.log("We must have called follower.close()");
      break;
    case 'error':
      console.log("Oh noes! Here's the error message: " + value);
      break;
  }
};

// Pass options and a callback
var follower = follow(
                '/var/log/syslog',
                { persistent: true },
                allEventsCallback);

// Totally redundant with the listener callback, but...
follower.on('all', allEventsCallback);

// We can also listen for specific events, using a
// different callback signature:
follower.on('line', function(filename, line) {
  console.log('Got a new line from '+filename+': '+line);
});

// ...
// When we're done, close the follower, or else it'll keep our
// process alive forever (if we opened it with persistent:true).
follower.close();
```

The simple example from above, in CoffeeScript:

```coffeescript
follow = require 'text-file-follower'

follower = follow '/var/log/syslog'

follower.on 'line', (filename, line) ->
  console.log "Got a new line from #{filename}: #{line}"

# ... and then eventually:
follower.close()
```

### Test utility

It gets very tedious to continually be adding lines to file (and deleting, and renaming, ...) in order to test callbacks/compatibility/etc. So I've created a little utility to ease this.

In the root directory you will find the file `tester.coffee`; to run it: `coffee tester.coffee`. You'll be greeted by a prompt that explains the basic function: hit \<Enter\> to write a new line to the file `test.test`. So if you create a follower for `test.test`, you can trigger new `'line'` events just by hitting \<Enter\>.

There are a few more commands that can be typed in as well:

* `stat`: Outputs `fs.stat` information for `test.test` (in case you want to see the inode value or size or mtime).
* `unlink`: Deletes `test.test`. In case you want to test delete-and-recreate. Note that hitting \<Enter\> again will re-create `test.test` (with a new line).
* `rename`: Renames `test.test`. In case you want to test rename-and-recreate. Note that hitting \<Enter\> again will re-create `test.test` (with a new line).
* `truncate`: Truncates `test.test`.


## Behaviour Notes

##### Line endings

`text-file-follower` works with both `\r\n` (Windows) and `\n` (everything else). Note that if both line ending types are present, `\r\n` will be used.

##### The definition of a "line"

Ends with a newline. So if text gets written that doesn't end with a newline, it won't trigger a `'line'` event (until a newline gets written). A "line" can be empty.

##### If multiple lines are written at once

They'll trigger separate `'line'` event emissions.

##### File that starts out non-existent

A follower can be created for a file that does not exist (yet, presumably). A `'success'` event will be emitted when the file is created, and any lines written to the file will start getting emitted at that point.

##### File that gets deleted during following

The follower will wait until it gets re-created and start following it again **from the start of the file**.

See comment below in the "OS Compatibility" section for bad behaviour on Linux.

##### File that gets renamed during following

The behaviour is basically the same as the deleted+recreated case: The follower will wait until it gets re-created and start following it again **from the start of the file**.

And again, see comment below in the "OS Compatibility" section for bad behaviour on Linux.

##### File shrinks during following

The current behaviour is that lines won't start getting emitted until the file grows past its previous size again.

This behaviour could be changed. (My understanding is that when log files get rotated they are renamed and then a fresh file is created. Which should be fine with the current behaviour.)

##### Pre-existing partial line

A file that looks like this when the follower starts is an example of what we mean by a "pre-existing partial line":

    line one\n
    line two\n
    line three has no newline

When the follower starts, it begins returning text from the end of the file. So if `, but now it does\n` gets appended to the file, that's the first line/text that will be emitted -- the `line three has no newline` part will not be included.

## OS Compatibility

The behaviour of `fs.watch` (which is what [watchit](https://github.com/TrevorBurnham/Watchit) is based on) is kinda sketchy. See the [bug list](https://github.com/joyent/node/issues/search?q=fs.watch&state=open).

Note: All observations are made while using the `{retain:true}` option with [watchit](https://github.com/TrevorBurnham/Watchit).

### Windows

* Test runs mostly succeed, but sometimes randomly fail (usually with a strange permissions error).
* After a rename or unlink (both of which trigger an `'unlink'` event), the following change triggers `'create'` and `'success'` events, but not a `'change'`. So another change it required before the first change will be read.

### Linux

* Tests pass, except...
* Due to a [watchit bug](https://github.com/TrevorBurnham/Watchit/issues/1) (which itself is due to a `fs.watch` oddity), when a watched file is deleted and recreated, the result will be two watchers.
* Probably also due to a watchit/`fs.watch` bug, after a watched file is renamed it gets permanently lost -- no more events come in for it (except `'close'`).

### OS X

* Tests pass. Works fairly well, but is quite slow. (Test runs typically take three times longer than Linux.)

## TODO

* Maybe create a Cakefile (steal watchit's)

* Make encoding an option?

## Feedback

All bugs, feature requests, feedback, etc., are welcome.

## License

http://adampritchard.mit-license.org/
