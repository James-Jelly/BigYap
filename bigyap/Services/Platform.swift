import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Pasteboard

/// The one clipboard call site the app needs, spelled the same on both
/// platforms. `UIPasteboard` replaces its contents; `NSPasteboard` requires an
/// explicit `clearContents()` first or the write is refused.
enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Haptics

/// Platform-neutral feedback. iOS drives Taptic Engine generators; macOS drives
/// the trackpad haptic performer, which is a no-op on hardware without one (a
/// mouse, or an external display setup), so call sites never have to care.
enum HapticStyle {
    case soft
    case light
    case medium
    case rigid

    #if os(iOS)
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .soft: return .soft
        case .light: return .light
        case .medium: return .medium
        case .rigid: return .rigid
        }
    }
    #endif
}

enum Haptics {
    @MainActor
    static func tap(_ style: HapticStyle = .soft) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    @MainActor
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    @MainActor
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}

// MARK: - Microphone permission

/// Mirrors `AVAudioApplication.recordPermission`, which is iOS-only. On macOS
/// the same three states come from `AVCaptureDevice` authorization, where
/// `.restricted` folds into denied — from the user's side both mean "can't
/// record, go change it in Settings".
enum MicPermission {
    case granted
    case denied
    case undetermined

    static var current: MicPermission {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
        #endif
    }

    static func request() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
}

// MARK: - System settings

enum SystemSettings {
    /// Opens the place where the user can restore microphone access. On iOS
    /// that's this app's own Settings page; on macOS there is no per-app pane,
    /// so it's the Microphone list in Privacy & Security.
    @MainActor
    static func openMicrophonePrivacy() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    #if os(macOS)
    /// Reveals BigYap itself in Finder, so the user can drag it into the
    /// Accessibility list. Needed because an app that hasn't been granted
    /// access may not appear there on its own, leaving "switch BigYap on" as
    /// advice about a row that isn't there.
    @MainActor
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Opens Privacy & Security > Accessibility, where the user grants BigYap
    /// the right to paste into other apps.
    @MainActor
    static func openAccessibilityPrivacy() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}

// MARK: - Naming

/// Used in first-run and privacy copy, which promises audio never leaves the
/// device and so has to name the right one.
enum DeviceNaming {
    #if os(iOS)
    static let thisDevice = "iPhone"
    static let systemName = "iOS"
    #elseif os(macOS)
    static let thisDevice = "Mac"
    static let systemName = "macOS"
    #endif
}

// MARK: - View shims

extension View {
    /// Autocapitalization is a software-keyboard concept, so the modifier is
    /// iOS-only. A Mac keyboard capitalizes nothing on its own.
    func noAutocapitalization() -> some View {
        #if os(iOS)
        return textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }

    /// `navigationBarTitleDisplayMode` doesn't exist on macOS, where titles are
    /// always inline in the window's toolbar anyway.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// Paints the Mac window's toolbar in the app canvas so the title bar reads
    /// as part of the page instead of a floating white strip. No-op on iOS,
    /// where the navigation bar already picks up the scroll content.
    func canvasToolbarBackground() -> some View {
        #if os(macOS)
        return toolbarBackground(Brand.canvas, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        #else
        return self
        #endif
    }
}
