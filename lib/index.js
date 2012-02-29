
/*
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
*/

(function() {
  var Follower, LineReader, default_options, events, follow, fs, util, watchit, _,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; },
    __slice = Array.prototype.slice;

  events = require('events');

  util = require('util');

  fs = require('fs');

  watchit = require('watchit');

  _ = require('underscore');

  default_options = {
    persistent: true,
    catchup: false
  };

  /*
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
  */

  follow = function(filename, options, listener) {
    var follower, lineReader, onchange, prev_mtime, prev_size, success_emitted, watcher;
    if (options == null) options = {};
    if (listener == null) listener = null;
    if (!(listener != null) && typeof options === 'function') {
      listener = options;
      options = {};
    }
    if (typeof filename !== 'string') {
      throw TypeError('`filename` must be a string');
    }
    if (typeof options !== 'object') {
      throw TypeError('if supplied, `options` must be an object');
    }
    if ((listener != null) && typeof listener !== 'function') {
      throw TypeError('if supplied, `listener` must be a function');
    }
    options = _.defaults(options, default_options);
    watcher = watchit(filename, {
      debounce: false,
      retain: true,
      persistent: options.persistent
    });
    follower = new Follower(watcher, filename);
    lineReader = new LineReader(follower);
    if (listener != null) follower.addListener('all', listener);
    prev_size = 0;
    prev_mtime = null;
    watcher.on('create', function() {
      return prev_size = 0;
    });
    watcher.on('unlink', function() {
      return prev_size = 0;
    });
    success_emitted = false;
    watcher.on('success', function() {
      if (!success_emitted) follower.emit('success');
      return success_emitted = true;
    });
    watcher.on('failure', function() {
      return follower.emit('error', 'watchit failure');
    });
    watcher.on('close', function() {
      return _.defer(function() {
        return follower.emit('close');
      });
    });
    fs.stat(filename, function(error, stats) {
      if (error != null) {
        if (error.code !== 'ENOENT') follower.emit('error', error);
        return;
      }
      if (!stats.isFile()) {
        follower.emit('error', 'not a file');
        return;
      }
      prev_mtime = stats.mtime;
      if (options.catchup) {
        return lineReader.read(prev_size, function(bytes_consumed) {
          return prev_size += bytes_consumed;
        });
      } else {
        return prev_size = stats.size;
      }
    });
    onchange = function(filename) {
      return fs.stat(filename, function(error, stats) {
        if (error != null) {
          if (error.code !== 'ENOENT') follower.emit('error', error);
          return;
        }
        if (stats.size <= prev_size) return;
        prev_mtime = stats.mtime;
        return lineReader.read(prev_size, function(bytes_consumed) {
          return prev_size += bytes_consumed;
        });
      });
    };
    watcher.on('change', onchange);
    return follower;
  };

  /*
  Helpers
  */

  /*
  The emitter that's returned from follow(). It can be used to listen for events,
  and it can also be used to close the follower.
  */

  Follower = (function(_super) {

    __extends(Follower, _super);

    function Follower(watcher, filename) {
      this.watcher = watcher;
      this.filename = filename;
    }

    Follower.prototype.close = function() {
      if (this.watcher != null) {
        return this.watcher.close();
      } else {
        return _.defer(function() {
          return emit('close');
        });
      }
    };

    Follower.prototype.emit = function() {
      var etc, event;
      event = arguments[0], etc = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      if (event === 'newListener') return;
      Follower.__super__.emit.apply(this, [event, this.filename].concat(__slice.call(etc)));
      return Follower.__super__.emit.apply(this, ['all', event, this.filename].concat(__slice.call(etc)));
    };

    return Follower;

  })(events.EventEmitter);

  /*
  This class is used to do the reading from the watched file. It emits lines via
  the `follower` constructor argument and keeps track of the number of bytes read
  via the `bytes_consumed_callback` argument to `read()`.
  An important function served by this class is to prevent multiple simultaneous
  reads on the same file (by the same follower).
  */

  LineReader = (function() {

    function LineReader(follower) {
      this.follower = follower;
      this._readstream = null;
    }

    LineReader.prototype.read = function(start_pos, bytes_consumed_callback) {
      var accumulated_data,
        _this = this;
      if ((this._readstream != null) && this._readstream.readable) return;
      accumulated_data = '';
      this._readstream = fs.createReadStream(this.follower.filename, {
        encoding: 'utf8',
        start: start_pos
      });
      this._readstream.on('error', function(error) {
        if (error.code !== 'ENOENT') return _this.follower.emit('error', error);
      });
      return this._readstream.on('data', function(new_data) {
        var bytes_consumed, lines, _ref;
        accumulated_data += new_data;
        _ref = _this._get_lines(accumulated_data), bytes_consumed = _ref[0], lines = _ref[1];
        accumulated_data = accumulated_data.slice(bytes_consumed);
        bytes_consumed_callback(bytes_consumed);
        return lines.forEach(function(line) {
          return _this.follower.emit('line', line);
        });
      });
    };

    /*
      Figure out if the text uses \n (unix) or \r\n (windows) newlines.
    */

    LineReader.prototype._deduce_newline_value = function(sample) {
      if (sample.indexOf('\r\n') >= 0) return '\r\n';
      return '\n';
    };

    /*
      Splits the text into complete lines (must end with newline).
      Returns a tuple of [bytes_consumed, [line1, line2, ...]]
    */

    LineReader.prototype._get_lines = function(text) {
      var bytes_consumed, lines, newline;
      newline = this._deduce_newline_value(text);
      lines = text.split(newline);
      lines.pop();
      if (lines.length === 0) return [0, []];
      bytes_consumed = _.reduce(lines, function(memo, line) {
        return memo + line.length;
      }, 0);
      bytes_consumed += lines.length * newline.length;
      return [bytes_consumed, lines];
    };

    return LineReader;

  })();

  module.exports = follow;

  module.exports.__get_debug_exports = function() {
    return {
      LineReader: LineReader
    };
  };

}).call(this);
