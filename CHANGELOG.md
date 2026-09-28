# Changelog

All notable changes to BigYap for Mac, newest first.

## 1.1.2 (2026-09-28)

- Remove filler words is now on by default, so every switch in Settings starts on for a
  new install. If you turned it off yourself, it stays off.

## 1.1.1 (2026-09-28)

- Settings > Playback now says "Needs Accessibility", with a button to set it up, when
  music can't be paused because the permission is missing.
- The Accessibility guide explains what to do when BigYap already looks switched on but
  isn't working: macOS can keep a grant from an older copy, so remove BigYap with − and
  add it again. It also mentions the Play/Pause key alongside the paste keystroke.

## 1.1 (2026-09-28)

- Pause music while recording: when a take starts (the Record button or the shortcut),
  whatever is playing pauses, then carries on when the take ends. BigYap presses the
  Play/Pause media key only when Core Audio shows another app sending audio out. It never
  presses it for calls or system sounds. Uses the same Accessibility permission as pasting. A switch in
  Settings > Playback, on by default.

## 1.0 (2026-09-08)

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
