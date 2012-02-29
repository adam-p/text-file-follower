
expect = require('chai').expect
fs = require('fs')
path = require('path')
_ = require('underscore')
Q = require('q')

# src if we want to test the original CS, lib if we want to test the JS
source_dir = '../src'

follow = require(source_dir)
follower_debug = follow.__get_debug_exports()


long_delay = (func) -> setTimeout func, 100
delay = _.defer #(func) -> setTimeout func, 100

appendSync = (filename, str) ->
  len = fs.statSync(filename).size
  fd = fs.openSync(filename, 'a')
  fs.writeSync(fd, str, len)
  fs.closeSync(fd)

appendAsync = (filename, str) ->
  _.defer -> appendSync(filename, str)


describe 'load-module', ->
  it 'should load when required', ->
    expect(follow).to.be.a('function')


describe 'LineReader', ->

  describe '#_deduce_newline_value', ->

    lineReader = new follower_debug.LineReader(null)

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(lineReader._deduce_newline_value(empty_string)).to.be.ok

    it 'should be correct with a string that is just a newline', ->
      newline = '\n'
      expect(lineReader._deduce_newline_value(newline)).to.equal(newline)
      newline = '\r\n'
      expect(lineReader._deduce_newline_value(newline)).to.equal(newline)

    it 'should default to unix-style if there are no newlines', ->
      no_newlines = 'foobar'
      expect(lineReader._deduce_newline_value(no_newlines)).to.equal('\n')

    it 'should correctly deduce Windows-style newlines', ->
      windows_newlines = 'foo\r\nbar'
      expect(lineReader._deduce_newline_value(windows_newlines)).to.equal('\r\n')

    it 'should correctly deduce unix-style newlines', ->
      windows_newlines = 'foo\nbar'
      expect(lineReader._deduce_newline_value(windows_newlines)).to.equal('\n')

  describe '#_get_lines', ->

    lineReader = new follower_debug.LineReader(null)

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(lineReader._get_lines(empty_string)).to.be.ok

    it "should return zero and an empty array if there is no newline", ->
      no_newlines = 'foobar'
      expect(lineReader._get_lines(no_newlines)).to.eql([0, []])

    it "should correctly split empty lines", ->
      only_newlines = '\n'
      expect(lineReader._get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\r\n'
      expect(lineReader._get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\n\n'
      expect(lineReader._get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

      only_newlines = '\r\n\r\n'
      expect(lineReader._get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

    it "should correctly split input that ends with a newline", ->

      newline_end = "foobar\n"
      result = lineReader._get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foobar\r\n"
      result = lineReader._get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foo\nbar\n"
      result = lineReader._get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

      newline_end = "foo\r\nbar\r\n"
      result = lineReader._get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

    it "should correctly split input that does not end with a newline", ->

      # A line isn't considered complete, and so shouldn't be counted, if it
      # doesn't end with a newline.

      not_newline_end = "foobar"
      result = lineReader._get_lines(not_newline_end)
      expect(result).to.eql([0, []])

      not_newline_end = "foo\nbar"
      result = lineReader._get_lines(not_newline_end)
      expect(result).to.eql(['foo\n'.length, ['foo']])

      not_newline_end = "foo\r\nbar"
      result = lineReader._get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\n'.length, ['foo']])

      not_newline_end = "foo\nbar\nasdf"
      result = lineReader._get_lines(not_newline_end)
      expect(result).to.eql(['foo\nbar\n'.length, ['foo', 'bar']])

      not_newline_end = "foo\r\nbar\r\nasdf"
      result = lineReader._get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\nbar\r\n'.length, ['foo', 'bar']])

  describe '#read', ->

  before ->
    # Create the test directories and files
    try
      fs.mkdirSync('fixtures')
    fs.writeFileSync('fixtures/a.test', '')

  beforeEach ->
    # Make the test files zero-size again
    fs.writeFileSync('fixtures/a.test', '')

  after ->
    fixture_filenames = fs.readdirSync('fixtures')
    for filename in fixture_filenames
      filename = path.join('fixtures', filename)
      if fs.statSync(filename).isDirectory()
        fs.rmdirSync(filename)
      else
        fs.unlinkSync(filename)

    it 'should be okay with an empty file', (done) ->
      follower_mock =
        filename: 'fixtures/a.test'

      lr = new follower_debug.LineReader(follower_mock)
      lr.read(0, -> throw new Error('should be no bytes read'))

      long_delay done

    it 'should read from the start of a non-empty file', (done) ->
      lines = ['this will', 'get read']
      line_index = 0
      lines_defer = Q.defer()

      follower_mock =
        filename: 'fixtures/a.test'
        emit: (type, value) ->
          expect(type).to.equal('line')
          expect(value).to.equal(lines[line_index++])
          if line_index == lines.length
            lines_defer.resolve()

      bytes_read = 0
      bytes_read_defer = Q.defer()
      bytes_consumed_callback = (num_bytes) ->
        bytes_read += num_bytes
        if bytes_read == (lines.join('\n')+'\n').length
          bytes_read_defer.resolve()

      appendSync('fixtures/a.test', lines.join('\n')+'\nno newline')

      lr = new follower_debug.LineReader(follower_mock)
      lr.read(0, bytes_consumed_callback)

      Q.all([lines_defer.promise, bytes_read_defer.promise]).then ->
        done()

    it 'should read from part way through a non-empty file', (done) ->
      lines = ['this will not get read', 'but this will', 'get read']
      line_index = 1
      lines_defer = Q.defer()

      follower_mock =
        filename: 'fixtures/a.test'
        emit: (type, value) ->
          expect(type).to.equal('line')
          expect(value).to.equal(lines[line_index++])
          if line_index == lines.length
            lines_defer.resolve()

      bytes_read = 0
      bytes_read_defer = Q.defer()
      bytes_consumed_callback = (num_bytes) ->
        bytes_read += num_bytes
        if bytes_read == (_.rest(lines).join('\n')+'\n').length
          bytes_read_defer.resolve()

      appendSync('fixtures/a.test', lines.join('\n')+'\nno newline')

      lr = new follower_debug.LineReader(follower_mock)
      lr.read(lines[0].length+1, bytes_consumed_callback)

      Q.all([lines_defer.promise, bytes_read_defer.promise]).then ->
        done()

    it 'should prevent multiple simultaneous reads', (done) ->
      lines = ['this will', 'get read']
      line_index = 0
      lines_defer = Q.defer()

      follower_mock =
        filename: 'fixtures/a.test'
        emit: (type, value) ->
          expect(type).to.equal('line')
          expect(value).to.equal(lines[line_index++])
          if line_index == lines.length
            lines_defer.resolve()

      bytes_read = 0
      bytes_read_defer = Q.defer()
      bytes_consumed_callback = (num_bytes) ->
        bytes_read += num_bytes
        if bytes_read == (lines.join('\n')+'\n').length
          bytes_read_defer.resolve()

      appendSync('fixtures/a.test', lines.join('\n')+'\nno newline')

      lr = new follower_debug.LineReader(follower_mock)
      lr.read(0, bytes_consumed_callback)

      # Start a second read immediately.
      # If this triggers any callbacks, something above will fail a check
      lr.read(0, bytes_consumed_callback)

      Q.all([lines_defer.promise, bytes_read_defer.promise]).then ->
        done()


describe 'text-file-follower', ->

  before ->
    # Create the test directories and files
    try
      fs.mkdirSync('fixtures')
    fs.mkdirSync('fixtures/testdir')
    fs.writeFileSync('fixtures/a.test', '')
    fs.writeFileSync('fixtures/b.test', '')
    fs.writeFileSync('fixtures/c.test', '')

  beforeEach ->
    # Make the test files zero-size again
    fs.writeFileSync('fixtures/a.test', '')
    fs.writeFileSync('fixtures/b.test', '')
    fs.writeFileSync('fixtures/c.test', '')

  after ->
    fixture_filenames = fs.readdirSync('fixtures')
    for filename in fixture_filenames
      filename = path.join('fixtures', filename)
      if fs.statSync(filename).isDirectory()
        fs.rmdirSync(filename)
      else
        fs.unlinkSync(filename)
    long_delay -> fs.rmdirSync('fixtures')

  describe '#follow', ->

    it "should reject bad arguments", ->
      # no args
      expect(-> follow()).to.throw(TypeError)
      # filename not a string
      expect(-> follow(123, {}, ->)).to.throw(TypeError)
      # options not an object
      expect(-> follow('foobar', 123, ->)).to.throw(TypeError)
      # listener not a function
      expect(-> follow('foobar', {}, 123)).to.throw(TypeError)
      # if two args, second arg is neither an object (options) nor a function (listener)
      expect(-> follow('foobar', 123)).to.throw(TypeError)

    it "should emit an error when given something that isn't a file", (done) ->
      f = follow('fixtures/testdir')
      f.on 'error', (filename, error) ->
        expect(error).to.equal('not a file')
        f.close()
        f.on 'close', -> done()

    it "should not throw an error when the file doesn't exist", (done) ->
      f = follow('foobar')
      # Should not be a success event
      f.on 'success', -> throw new Error('success is bad here')
      f.close()
      f.on 'close', -> done()

    it "should start successfully in a simple scenario", (done) ->
      f = follow('fixtures/a.test')
      expect(f).to.be.ok
      f.on 'success', ->
        f.close()
        f.on 'close', -> done()

    it "should read lines from a fresh file successfully, using the emitter", (done) ->
      line_count = 0
      next = null
      received_lines = []

      f = follow('fixtures/a.test')
      expect(f).to.be.ok
      f.on 'error', (filename, error) ->
        throw new Error(error)

      f.on 'line', (filename, line) ->
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        _.defer next

      f.on 'success', ->
        # no newline
        appendSync('fixtures/a.test', 'abc')
        long_delay ->
          expect(line_count).to.equal(0)

          appendAsync('fixtures/a.test', '\n')
          next = ->
            expect(line_count).to.equal(1)
            expect(received_lines.shift()).to.equal('abc')

            appendAsync('fixtures/a.test', 'def\n')
            next = ->
              expect(line_count).to.equal(2)
              expect(received_lines.shift()).to.equal('def')

              call_count = 0
              appendAsync('fixtures/a.test', 'ghi\njkl\n')
              next = ->
                # This will get called twice.
                if call_count == 0
                  expect(received_lines.shift()).to.equal('ghi')
                  call_count = 1
                else if call_count == 1
                  expect(received_lines.shift()).to.equal('jkl')

                  # Finished
                  f.on 'close', -> done()
                  f.close()
                else
                  throw Error('bad line_count')

    it "should read lines from a file, using the listener callback", (done) ->
      line_count = 0
      next = null
      received_lines = []
      expected_event = ''
      curr_filename = ''

      listener = (event, filename, value) ->
        expect(event).to.equal(expected_event)
        expect(filename).to.equal(curr_filename)
        if event == 'line'
          line_count++
          received_lines.push(value)
        else if event == 'error'
          throw new Error(value) # won't actually get here, since the expected_event check will fail
        if next? then _.defer next

      curr_filename = 'fixtures/a.test'

      f = follow('fixtures/a.test', listener)
      expect(f).to.be.ok

      expected_event = 'success'
      next = ->

        expected_event = 'line'
        appendAsync('fixtures/a.test', 'abc\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          expected_event = 'line'
          appendAsync('fixtures/a.test', 'def\n')
          next = ->
            expect(line_count).to.equal(2)
            expect(received_lines.shift()).to.equal('def')

            expected_event = 'close'
            f.close()
            next = ->
              done()

    it "should read lines from a file, using the 'all' listener", (done) ->
      line_count = 0
      next = null
      received_lines = []
      expected_event = ''
      curr_filename = ''

      listener = (event, filename, value) ->
        expect(event).to.equal(expected_event)
        expect(filename).to.equal(curr_filename)
        if event == 'line'
          line_count++
          received_lines.push(value)
        else if event == 'error'
          throw new Error(value) # won't actually get here, since the expected_event check will fail
        if next? then _.defer next

      curr_filename = 'fixtures/a.test'

      f = follow('fixtures/a.test')
      expect(f).to.be.ok

      f. on 'all', listener

      expected_event = 'success'
      next = ->

        expected_event = 'line'
        appendAsync('fixtures/a.test', 'abc\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          expected_event = 'line'
          appendAsync('fixtures/a.test', 'def\n')
          next = ->
            expect(line_count).to.equal(2)
            expect(received_lines.shift()).to.equal('def')

            expected_event = 'close'
            f.close()
            next = ->
              done()

    it "should read lines from the end of a non-empty file", (done) ->
      line_count = 0
      next = null
      received_lines = []

      listener = (filename, line) ->
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        _.defer next

      appendSync('fixtures/a.test', 'will not\nget read\n')

      f = follow('fixtures/a.test')
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()

      f.on 'line', listener

      f.on 'success', ->
        appendAsync('fixtures/a.test', 'abc\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          appendAsync('fixtures/a.test', 'def\n')
          next = ->
            expect(line_count).to.equal(2)
            expect(received_lines.shift()).to.equal('def')

            f.on 'close', -> done()
            f.close()

    it "should successfully work with two different files at once", (done) ->
      line_count = 0

      f1_line = 'f1'
      f1_filename = 'fixtures/a.test'
      f1 = follow(f1_filename)
      f1.on 'error', -> throw new Error()

      f1_line_deferred = Q.defer()
      f1.on 'line', (filename, line) ->
        expect(filename).to.equal(f1_filename)
        expect(line).to.equal(f1_line)
        line_count++
        f1_line_deferred.resolve()

      f2_line = 'f2'
      f2_filename = 'fixtures/b.test'
      f2 = follow(f2_filename)
      f2.on 'error', -> throw new Error()

      f2_line_deferred = Q.defer()
      f2.on 'line', (filename, line) ->
        expect(filename).to.equal(f2_filename)
        expect(line).to.equal(f2_line)
        line_count++
        f2_line_deferred.resolve()

      f1.on 'success', ->
        appendAsync(f1_filename, f1_line+'\n')

      f2.on 'success', ->
        appendAsync(f2_filename, f2_line+'\n')

      Q.all([f1_line_deferred.promise, f2_line_deferred.promise]).then ->
        expect(line_count).to.equal(2)
        f1.close()
        f2.close()

      f1_close_deferred = Q.defer()
      f1.on 'close', f1_close_deferred.resolve

      f2_close_deferred = Q.defer()
      f2.on 'close', f2_close_deferred.resolve

      Q.all([f1_close_deferred.promise, f2_close_deferred.promise]).then ->
        done()

    it "should be able to put two watchers on the same file", (done) ->
      line_count = 0

      curr_line = 'foobar'
      curr_filename = 'fixtures/a.test'

      f1 = follow(curr_filename)
      f2 = follow(curr_filename)

      f1.on 'error', -> throw new Error()
      f2.on 'error', -> throw new Error()

      f1_line_deferred = Q.defer()
      f1.on 'line', (filename, line) ->
        expect(filename).to.equal(curr_filename)
        expect(line).to.equal(curr_line)
        line_count++
        f1_line_deferred.resolve(line)

      f2_line_deferred = Q.defer()
      f2.on 'line', (filename, line) ->
        expect(filename).to.equal(curr_filename)
        expect(line).to.equal(curr_line)
        line_count++
        f2_line_deferred.resolve(line)

      f1_success_deferred = Q.defer()
      f1.on 'success', f1_success_deferred.resolve

      f2_success_deferred = Q.defer()
      f2.on 'success', f2_success_deferred.resolve

      Q.all([f1_success_deferred.promise, f2_success_deferred.promise]).then ->
        appendAsync(curr_filename, curr_line+'\n')

      f1_close_deferred = Q.defer()
      f1.on 'close', f1_close_deferred.resolve

      f2_close_deferred = Q.defer()
      f2.on 'close', f2_close_deferred.resolve

      Q.all([f1_line_deferred.promise, f2_line_deferred.promise]).then ->
        expect(line_count).to.equal(2)
        f1.close()
        f2.close()

      Q.all([f1_close_deferred.promise, f2_close_deferred.promise]).then ->
        done()

    it "should successfully close and re-open a follower", (done) ->
      line_count = 0
      next = null
      curr_filename = ''
      received_lines = []

      listener = (filename, line) ->
        line_count++
        expect(filename).to.equal(curr_filename)
        received_lines.push(line)
        _.defer next

      curr_filename = 'fixtures/a.test'

      f = follow(curr_filename)
      expect(f).to.be.ok

      f.on 'error', -> throw new Error()
      f.on 'line', listener

      f.on 'success', ->
        appendAsync(curr_filename, 'abc\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          # Close
          f.close()
          f.on 'close', ->

            # Re-open
            line_count = 0
            f = follow(curr_filename)
            expect(f).to.be.ok

            f.on 'error', -> throw new Error()
            f.on 'line', listener

            f.on 'success', ->

              appendAsync(curr_filename, 'def\n')
              next = ->
                expect(line_count).to.equal(1)
                expect(received_lines.shift()).to.equal('def')

                f.close()
                f.on 'close', -> done()

    it "should asynchronously emit a close event", (done) ->
      curr_filename = 'fixtures/a.test'
      f = follow(curr_filename)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()

      f.on 'success', ->
        test = false
        f.on 'close', ->
          # This should only get hit after all of the synchronous code below completes.
          expect(test).to.be.true
          done()

        f.close()
        test = true

    it "should 'retain' a file that gets deleted and re-created", (done) ->

      if process.platform == 'linux'
        console.log('!!!! Fails on Linux due to watchit bug ("expected 3 to equal 2") !!!!')
        return done()

      line_count = 0
      next = null
      curr_filename = ''
      received_lines = []

      listener = (filename, line) ->
        line_count++
        expect(filename).to.equal(curr_filename)
        received_lines.push(line)
        _.defer next

      curr_filename = 'fixtures/a.test'
      f = follow(curr_filename)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()
      f.on 'line', listener

      success_listener_called = false

      f.on 'success', ->

        # Our follower should only emit 'success' once, even when the file gets
        # deleted and re-created. (watchit emits 'success' more than once.)
        expect(success_listener_called).to.equal(false)
        success_listener_called = true

        appendAsync(curr_filename, 'qwe\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('qwe')

          # Delete the file
          fs.unlink curr_filename, (error) ->
            if error? then throw new Error(error)

            long_delay ->
              # Create the file and put a line in it.
              fs.writeFileSync(curr_filename, '')
              expect(fs.statSync(curr_filename).size).to.equal(0)

              long_delay ->
                _.defer ->
                  appendSync(curr_filename, 'rty\n')
                  expect(fs.statSync(curr_filename).size).to.equal(4)

                next = ->
                  expect(line_count).to.equal(2)
                  expect(received_lines.shift()).to.equal('rty')

                  f.close()
                  f.on 'close', -> done()

    it "should follow a file that does not initially exist", (done) ->

      line_count = 0
      next = null
      curr_filename = ''
      expected_event = ''
      received_lines = []

      listener = (event, filename, value) ->
        expect(event).to.equal(expected_event)
        expect(filename).to.equal(curr_filename)
        if event == 'line'
          line_count++
          received_lines.push(value)
        else if event == 'error'
          throw new Error(value) # won't actually get here, since the expected_event check will fail
        if next? then _.defer next

      curr_filename = 'fixtures/a.test'

      # Delete the file before following
      fs.unlink curr_filename, ->

        f = follow(curr_filename)
        expect(f).to.be.ok

        f.on 'all', listener

        # We're not going to set `expected_event` to `'success'` yet, because we
        # shouldn't get it until the file is created. In fact, there should be no
        # events. We'll call _.defer to let any possible erroneous events come through.

        _.defer ->

          # Create the file
          fs.writeFileSync(curr_filename, '')

          success_listener_called = false
          expected_event = 'success'
          next = ->

            # Our follower should only emit 'success' once.
            expect(success_listener_called).to.equal(false)
            success_listener_called = true

            appendAsync(curr_filename, 'abc\n')
            expected_event = 'line'
            next = ->
              expect(line_count).to.equal(1)
              expect(received_lines.shift()).to.equal('abc')

              appendAsync(curr_filename, 'def\n')
              expected_event = 'line'
              next = ->
                expect(line_count).to.equal(2)
                expect(received_lines.shift()).to.equal('def')

                f.close()
                expected_event = 'close'
                next = -> done()

    it "should 'retain' a file(name) that gets renamed and re-created", (done) ->

      if process.platform == 'linux'
        console.log('!!!! Fails on Linux due to watchit bug (test times out) !!!!')
        return done()

      line_count = 0
      next = null
      curr_filename = ''
      received_lines = []

      listener = (filename, line) ->
        line_count++
        expect(filename).to.equal(curr_filename)
        received_lines.push(line)
        _.defer next

      curr_filename = 'fixtures/a.test'
      f = follow(curr_filename)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()
      f.on 'line', listener

      success_listener_called = false

      f.on 'success', ->

        # Our follower should only emit 'success' once, even when the file gets
        # renamed and re-created. (watchit emits 'success' more than once.)
        expect(success_listener_called).to.equal(false)
        success_listener_called = true

        appendAsync(curr_filename, 'qwe\n')
        next = ->
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('qwe')

          # Rename the file
          fs.rename curr_filename, curr_filename+(new Date().getTime()), (error) ->
            if error? then throw new Error(error)

            long_delay ->
              # Re-create the file and put a line in it.
              fs.writeFileSync(curr_filename, '')
              expect(fs.statSync(curr_filename).size).to.equal(0)

              long_delay ->
                _.defer ->
                  appendSync(curr_filename, 'rty\n')
                  expect(fs.statSync(curr_filename).size).to.equal(4)

                next = ->
                  expect(line_count).to.equal(2)
                  expect(received_lines.shift()).to.equal('rty')

                  f.close()
                  f.on 'close', -> done()

    it "should 'catchup' a non-empty file", (done) ->
      line_count = 0
      next = null
      received_lines = []

      listener = (filename, line) ->
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        _.defer next

      appendSync('fixtures/a.test', 'this will\nget read\n')

      f = follow('fixtures/a.test', { catchup: true })
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()

      f.on 'line', listener

      f.on 'success', ->
        appendAsync('fixtures/a.test', 'abc\n')

      lines = ['this will', 'get read', 'abc']
      next = ->
        expect(received_lines.shift()).to.equal(lines.shift())

        if lines.length == 0
          f.on 'close', -> done()
          f.close()
