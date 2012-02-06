
expect = require('chai').expect
horaa = require('horaa')


describe 'text-file-follower', ->

  describe '#load-module', ->

    it 'should load when required', ->
      expect(require('../lib/index')).to.be.ok

  follower_debug = require('../lib/index').__get_debug_exports()

  describe '#deduce_newline_value', ->

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(follower_debug.deduce_newline_value(empty_string)).to.be.ok

    it 'should be correct with a string that is just a newline', ->
      newline = '\n'
      expect(follower_debug.deduce_newline_value(newline)).to.equal(newline)
      newline = '\r\n'
      expect(follower_debug.deduce_newline_value(newline)).to.equal(newline)

    it 'should default to unix-style if there are no newlines', ->
      no_newlines = 'foobar'
      expect(follower_debug.deduce_newline_value(no_newlines)).to.equal('\n')

    it 'should correctly deduce Windows-style newlines', ->
      windows_newlines = 'foo\r\nbar'
      expect(follower_debug.deduce_newline_value(windows_newlines)).to.equal('\r\n')

    it 'should correctly deduce unix-style newlines', ->
      windows_newlines = 'foo\nbar'
      expect(follower_debug.deduce_newline_value(windows_newlines)).to.equal('\n')

  describe '#get_lines', ->

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(follower_debug.get_lines(empty_string)).to.be.ok

    it "should return zero and an empty array if there is no newline", ->
      no_newlines = 'foobar'
      expect(follower_debug.get_lines(no_newlines)).to.eql([0, []])

    it "should correctly split empty lines", ->
      only_newlines = '\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\r\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\n\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

      only_newlines = '\r\n\r\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

    it "should correctly split input that ends with a newline", ->

      newline_end = "foobar\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foobar\r\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foo\nbar\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

      newline_end = "foo\r\nbar\r\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

    it "should correctly split input that does not end with a newline", ->

      # A line isn't considered complete, and so shouldn't be counted, if it 
      # doesn't end with a newline.

      not_newline_end = "foobar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql([0, []])

      not_newline_end = "foo\nbar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\n'.length, ['foo']])

      not_newline_end = "foo\r\nbar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\n'.length, ['foo']])

      not_newline_end = "foo\nbar\nasdf"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\nbar\n'.length, ['foo', 'bar']])

      not_newline_end = "foo\r\nbar\r\nasdf"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\nbar\r\n'.length, ['foo', 'bar']])

  describe '#follow', ->

    fsHoraa = horaa('fs')

    follower = require('../lib/index')

    it "should reject bad arguments", ->
      # no args
      expect(-> follower.follow()).to.throw(TypeError)
      # filename not a string
      expect(-> follower.follow(123, {}, ->)).to.throw(TypeError)
      # options not an object
      expect(-> follower.follow('foobar', 123, ->)).to.throw(TypeError)
      # listener not a function
      expect(-> follower.follow('foobar', {}, 123)).to.throw(TypeError)
      # if two args, second arg is neither an object (options) nor a function (listener)
      expect(-> follower.follow('foobar', 123)).to.throw(TypeError)

    it "should handle the optional arguments correctly", ->
      # need mocking -- enough to create the follower and then close it
      #expect(-> follower.follow('foobar', ->)).to.throw(Error)
      true

    it "should throw an error when given something that isn't a file", ->
      fsHoraa.hijack('statSync', () -> return isFile: -> false)
      expect(-> follower.follow('foobar', ->)).to.throw(Error)
      fsHoraa.restore('statSync')

    it "should throw an error when the file doesn't exist", ->
      expect(-> follower.follow('foobar', ->)).to.throw(Error)
