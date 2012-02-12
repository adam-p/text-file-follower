IS_CYGWIN := $(shell uname | sed -e '/.*\(CYGWIN\).*/!d;s//\1/')

COFFEE := coffee
MOCHA := mocha

ifneq ($(IS_CYGWIN),)
	COFFEE := ../node_modules/.bin/coffee.cmd
	MOCHA := ../node_modules/.bin/mocha.cmd
endif


lib/%.js: src/%.coffee
	$(COFFEE) -c -o lib src/*.coffee

test: lib/*.js
	$(MOCHA) --bail --require chai --reporter list test/*.coffee
.PHONY: test
