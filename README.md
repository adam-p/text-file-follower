

# TODO

- Create manual test app
- Move .coffee to /src and add make target that compiles to /lib.
- Multiple live watchers on the same file seems to be a problem (issue with watchit?)
  - Add a test
- Add 'catchup' (process whole file first) feature.
- Probably switch to basic fs.watch rather than watchit.
  - Not sure what benefit it confers if not using debounce.
- Run through linter.
- Properly handle pre-existing partial line when watcher first starts
  - Or state explicitly that it won't be handled
- Make a behaviour rule for if the file shrinks
  - Don't start returning lines until it reaches the previous maximum length?
  - Start returning lines when the file starts growing again? (Prolly that.)
- Make encoding an option?

# Observations

Note: All while using {retain:true}.

## Windows
- After a rename or unlink (both of which trigger an 'unlink' event), the following change triggers 'create' and 'success' events, but not a 'change'. So another change it required before the first change will be read.