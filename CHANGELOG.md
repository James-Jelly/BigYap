# Changelog

All notable changes to BigYap for Mac, newest first.

## 1.0 (in progress)

First public release of the source.

- System wide dictation: press ⌥ Space (configurable) in any app, talk, press again, and
  the text is pasted into the focused field. Falls back to the clipboard without the
  Accessibility permission.
- Live transcription with Apple's on device `SpeechAnalyzer`, with a warm standby session
  so the shortcut responds instantly.
- Cleanup pipeline, each step a switch: trim silence, remove filler words, correct with a
  custom vocabulary.
- Local history with search, favourites, inline editing, undo delete and export as text.
- App Sandbox, no network code, no third party dependencies, no data collected.
