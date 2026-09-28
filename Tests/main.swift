// Runnable logic-regression suite for bigyap's pure processing features.
// Run with: ./Tests/run-tests.sh
//
// This compiles the real Services sources (FuzzyMatcher, TranscriptProcessor,
// VoiceActivityTrimmer) together with these assertions, so it always tests the
// shipping code. The checks map 1:1 to Swift Testing `#expect`s if you later
// add an Xcode unit-test target.
import Foundation

var failures = 0
@MainActor func check(_ cond: Bool, _ name: String) {
    print((cond ? "PASS" : "FAIL") + ": " + name)
    if !cond { failures += 1 }
}

// MARK: FuzzyMatcher
check(FuzzyMatcher.levenshtein("kitten", "sitting") == 3, "levenshtein kitten/sitting = 3")
check(FuzzyMatcher.soundex("Robert") == "R163", "soundex Robert = R163")
check(FuzzyMatcher.soundex("Rupert") == "R163", "soundex Rupert = R163")
check(FuzzyMatcher.bestMatch(for: "kubernetis", in: ["Kubernetes"]) == "Kubernetes", "fuzzy kubernetis -> Kubernetes")
check(FuzzyMatcher.bestMatch(for: "hello", in: ["Kubernetes"]) == nil, "no match for 'hello'")
check(FuzzyMatcher.bestMatch(for: "Kubernetes", in: ["Kubernetes"]) == nil, "exact match returns nil")

// MARK: TranscriptProcessor — filler removal
let f = TranscriptProcessor.removeFillerWords("um so uh this is, you know, a test", fillers: ["um", "uh", "you know"])
check(!f.lowercased().contains("you know"), "filler removes 'you know'")
check(!f.lowercased().contains("um "), "filler removes 'um'")
check(f.lowercased().contains("test"), "filler keeps 'test'")

// MARK: TranscriptProcessor — vocabulary
let v = TranscriptProcessor.applyVocabulary("i love swift data and kubernetis", vocabulary: ["SwiftData", "Kubernetes"])
check(v.contains("SwiftData"), "vocab bigram 'swift data' -> SwiftData")
check(v.contains("Kubernetes"), "vocab fuzzy 'kubernetis' -> Kubernetes")

// MARK: TranscriptProcessor — tidy
check(TranscriptProcessor.tidy("hello world") == "Hello world", "tidy capitalizes first letter")
check(TranscriptProcessor.tidy("hello  ,  world .") == "Hello, world.", "tidy fixes spacing/punctuation")

// MARK: TranscriptProcessor — paragraph splitting
let para = TranscriptProcessor.splitIntoParagraphs("Hey there. How are you? I'm fine.")
check(para == "Hey there.\n\nHow are you?\n\nI'm fine.", "splits sentences with a blank line between")
check(TranscriptProcessor.splitIntoParagraphs("Just one sentence here.") == "Just one sentence here.", "single sentence unchanged")
check(!TranscriptProcessor.splitIntoParagraphs("Meet at 3.14 p.m. today.").contains("\n"), "decimals/abbreviations don't split")
let paraProc = TranscriptProcessor(paragraphPerSentence: true)
check(paraProc.process("hello world. this is a test.") == "Hello world.\n\nThis is a test.", "pipeline applies paragraph split after tidy")

// MARK: TranscriptProcessor — full pipeline
let proc = TranscriptProcessor(vocabulary: ["SwiftData"], fillerWords: ["um", "uh"], correctVocabulary: true, removeFillers: true)
let out = proc.process("um so i used swift data uh yesterday")
check(out.contains("SwiftData"), "process applies vocab")
check(!out.lowercased().contains(" um "), "process removes filler")
check(out.first.map(\.isUppercase) ?? false, "process capitalizes")

// MARK: VoiceActivityTrimmer
var samples = [Float]()
samples += Array(repeating: 0.0, count: 8000)                       // 0.5s silence
for i in 0..<8000 { samples.append(0.3 * sinf(Float(i) * 0.2)) }    // 0.5s tone
samples += Array(repeating: 0.0, count: 8000)                       // 0.5s silence
let r = VoiceActivityTrimmer().trim(samples, sampleRate: 16000)
check(r.didTrim, "VAD trims silence")
check(r.samples.count < samples.count, "VAD reduces sample count")
check(r.removedDuration > 0.3, "VAD removed > 0.3s of silence")

let r2 = VoiceActivityTrimmer().trim(Array(repeating: 0.0, count: 24000), sampleRate: 16000)
check(!r2.didTrim, "VAD all-silence returns original (no destructive trim)")

// MARK: TranscriptEditPolicy
check(TranscriptEditPolicy.committedText(edited: "new text", previous: "old") == "new text", "edit policy saves a real change")
check(TranscriptEditPolicy.committedText(edited: "same", previous: "same") == nil, "edit policy no-ops when unchanged")
check(TranscriptEditPolicy.committedText(edited: "", previous: "old") == nil, "edit policy rejects empty")
check(TranscriptEditPolicy.committedText(edited: "  \n\t ", previous: "old") == nil, "edit policy rejects whitespace-only")
check(TranscriptEditPolicy.committedText(edited: " padded ", previous: "old") == " padded ", "edit policy preserves surrounding whitespace of real text")

// MARK: PlaybackPausePolicy
func audio(_ pid: Int32, _ bundle: String, output: Bool = true, input: Bool = false) -> AudioProcessActivity {
    AudioProcessActivity(pid: pid, bundleID: bundle, isRunningOutput: output, isRunningInput: input)
}
let me: Int32 = 100
check(!PlaybackPausePolicy.isOtherAudioPlaying([], ownPID: me), "pause policy: silence means no pause")
check(PlaybackPausePolicy.isOtherAudioPlaying([audio(200, "com.spotify.client")], ownPID: me), "pause policy: a player's output pauses")
check(PlaybackPausePolicy.isOtherAudioPlaying([audio(201, "com.apple.WebKit.GPU")], ownPID: me), "pause policy: a Safari tab's output pauses")
check(!PlaybackPausePolicy.isOtherAudioPlaying([audio(200, "com.spotify.client", output: false)], ownPID: me), "pause policy: an idle player is ignored")
check(!PlaybackPausePolicy.isOtherAudioPlaying([audio(me, "com.jellydevops.bigyap.bigyap")], ownPID: me), "pause policy: BigYap's own output is ignored")
check(!PlaybackPausePolicy.isOtherAudioPlaying([audio(300, "us.zoom.xos", input: true)], ownPID: me), "pause policy: a call (output + input) is ignored")
check(!PlaybackPausePolicy.isOtherAudioPlaying([audio(400, "systemsoundserverd"), audio(401, "com.apple.VoiceOver")], ownPID: me), "pause policy: alert sounds and VoiceOver are ignored")
check(PlaybackPausePolicy.isOtherAudioPlaying([audio(300, "us.zoom.xos", input: true), audio(200, "com.apple.Music")], ownPID: me), "pause policy: music alongside a call still pauses")

// MARK: AppSettings — fresh install defaults
// A throwaway suite stands in for a first launch: nothing stored, so every
// toggle shows its default. Each user-facing switch should start on.
let freshSuite = "bigyap-tests-\(UUID().uuidString)"
let freshDefaults = UserDefaults(suiteName: freshSuite)!
let fresh = AppSettings(defaults: freshDefaults)
check(fresh.removeFillerWords, "fresh install: remove filler words on")
check(fresh.paragraphPerSentence, "fresh install: new line per sentence on")
check(fresh.appendTrailingSpace, "fresh install: append trailing space on")
check(fresh.copyToClipboard, "fresh install: copy transcript on")
check(fresh.trimSilence, "fresh install: trim silence on")
check(fresh.correctWithVocabulary, "fresh install: correct with vocabulary on")
check(fresh.globalHotKeyEnabled, "fresh install: system-wide dictation on")
check(fresh.pausePlaybackWhileRecording, "fresh install: pause music on")
freshDefaults.set(false, forKey: "removeFillerWords")
check(!AppSettings(defaults: freshDefaults).removeFillerWords, "a stored choice beats the default")
freshDefaults.removePersistentDomain(forName: freshSuite)

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
