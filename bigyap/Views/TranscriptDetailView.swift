import SwiftData
import SwiftUI

struct TranscriptDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var entry: TranscriptEntry

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.brand(.caption, weight: .medium))
                        .foregroundStyle(Brand.inkSecondary)
                    if isEditing {
                        TextEditor(text: $draft)
                            .font(.brandBody)
                            .foregroundStyle(Brand.ink)
                            .tint(Brand.blush)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .focused($editorFocused)
                    } else {
                        Text(entry.text)
                            .font(.brandBody)
                            .foregroundStyle(Brand.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .softCard()
                .padding(Spacing.lg)
            }
        }
        .navigationTitle("Transcript")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        commitEdit()
                    } else {
                        draft = entry.text
                        isEditing = true
                        editorFocused = true
                    }
                }
                .font(.brand(.subheadline, weight: .semibold))
                .tint(Brand.blush)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Clipboard.copy(currentText)
                        entry.copiedToClipboard = true
                        try? modelContext.save()
                        Haptics.tap()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: currentText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(Brand.blush)
            }
        }
    }

    /// Copy/Share always act on what's on screen — the in-progress draft while
    /// editing, the saved text otherwise.
    private var currentText: String {
        isEditing ? draft : entry.text
    }

    /// Saves the draft back to the same entry; a whitespace-only or unchanged
    /// draft is discarded and the previous text kept.
    private func commitEdit() {
        editorFocused = false
        isEditing = false
        guard let text = TranscriptEditPolicy.committedText(edited: draft, previous: entry.text) else { return }
        entry.text = text
        try? modelContext.save()
        Haptics.tap()
    }
}
