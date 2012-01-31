
expect = require('chai').expect

describe 'index', ->
	describe '#load-module', ->
		it 'should load when required', ->
			expect(require('../lib/index')).to.be.ok
