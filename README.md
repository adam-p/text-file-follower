

# TODO

- Multiple live watchers on the same file seems to be a problem (issue with watchit?)
  - Add a test
- Add 'catchup' (process whole file first) feature.
- Probably switch to basic fs.watch rather than watchit.
  - Not sure what benefit it confers if not using deb ounce.
- Properly handle pre-existing partial line when watcher first starts
  - Or state explicitly that it won't be handled
- Make a behaviour rule for if the file shrinks
  - Don't start returning lines until it reaches the previous maximum length?
  - Start returning lines when the file starts growing again? (Prolly that.)
- Make encoding an option?
