
test:
	mocha --timeout 10000 --require chai --reporter list test/*.coffee

.PHONY: test
