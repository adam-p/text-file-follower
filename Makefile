
lib/%.js: src/%.coffee
	coffee -c -o lib src/*.coffee

test: lib/*.js
	mocha --require chai --reporter list test/*.coffee
.PHONY: test
