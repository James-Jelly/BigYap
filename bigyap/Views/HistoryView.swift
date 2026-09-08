import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptEntry.createdAt, order: .reverse) private var entries: [TranscriptEntry]
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var pendingDeletedID: PersistentIdentifier?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var confirmDeleteAll = false

    private var filtered: [TranscriptEntry] {
        entries.filter { entry in
            guard entry.persistentModelID != pendingDeletedID else { return false }
            guard !favoritesOnly || entry.favorite else { return false }
            guard !searchText.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasFavorites: Bool {
        entries.contains { $0.favorite }
    }

    private var exportText: String {
        filtered
            .map { entry in
                "\(entry.createdAt.formatted(date: .abbreviated, time: .shortened))\n\(entry.text)"
            }
            .joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.canvas.ignoresSafeArea()

                if entries.isEmpty {
                    EmptyHistoryView()
                } else if favoritesOnly && !hasFavorites {
                    EmptyFavoritesView()
                } else {
                    List {
                        ForEach(filtered) { entry in
                            ZStack {
                                NavigationLink(value: entry) { EmptyView() }.opacity(0)
                                TranscriptCard(entry: entry) {
                                    entry.favorite.toggle()
                                    try? modelContext.save()
                                    Haptics.tap()
                                } copy: {
                                    copy(entry)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                            .swipeActions(edge: .leading) {
                                Button {
                                    entry.favorite.toggle()
                                    try? modelContext.save()
                                    Haptics.tap()
                                } label: {
                                    Label(entry.favorite ? "Unfavorite" : "Favorite",
                                          systemImage: entry.favorite ? "heart.slash" : "heart")
                                }
                                .tint(Brand.blush)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    copy(entry)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(Brand.sage)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: TranscriptEntry.self) { entry in
                        TranscriptDetailView(entry: entry)
                    }
                    .searchable(text: $searchText, prompt: "Search transcripts")
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        favoritesOnly.toggle()
                        Haptics.tap()
                    } label: {
                        Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    }
                    .tint(Brand.blush)
                    .accessibilityLabel(favoritesOnly ? "Show all transcripts" : "Show favorites")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: exportText) {
                            Label("Export all", systemImage: "square.and.arrow.up")
                        }
                        .disabled(filtered.isEmpty)
                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label("Delete all", systemImage: "trash")
                        }
                        .disabled(entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(Brand.blush)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if pendingDeletedID != nil {
                    UndoDeleteBanner {
                        undoDelete()
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: pendingDeletedID)
            .confirmationDialog(
                "Delete all transcripts?",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { deleteAll() }
            } message: {
                Text("This permanently removes every transcript from this device. This can't be undone.")
            }
            .onDisappear {
                finalizePendingDeletion()
            }
        }
    }

    private func deleteAll() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeletedID = nil
        try? modelContext.delete(model: TranscriptEntry.self)
        try? modelContext.save()
        Haptics.warning()
    }

    private func delete(_ entry: TranscriptEntry) {
        finalizePendingDeletion()
        pendingDeletedID = entry.persistentModelID
        pendingDeleteTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            finalizePendingDeletion(matching: entry.persistentModelID)
        }
        Haptics.tap()
    }

    private func undoDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeletedID = nil
        Haptics.tap()
    }

    private func finalizePendingDeletion() {
        guard let id = pendingDeletedID else { return }
        finalizePendingDeletion(matching: id)
    }

    private func finalizePendingDeletion(matching id: PersistentIdentifier) {
        guard pendingDeletedID == id else { return }
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeletedID = nil

        guard let entry = modelContext.model(for: id) as? TranscriptEntry else { return }
        modelContext.delete(entry)
        try? modelContext.save()
    }

    /// Shared by the card's copy button and the trailing swipe action, so both
    /// also mark the entry as copied.
    private func copy(_ entry: TranscriptEntry) {
        Clipboard.copy(entry.text)
        entry.copiedToClipboard = true
        try? modelContext.save()
        Haptics.tap()
    }
}

private struct TranscriptCard: View {
    var entry: TranscriptEntry
    var toggleFavorite: () -> Void
    var copy: () -> Void

    /// Flips the copy glyph to a tick for a moment so the tap has a visible
    /// result — nothing else on screen changes when text lands on the clipboard.
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(entry.createdAt, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.brand(.caption, weight: .medium))
                    .foregroundStyle(Brand.inkSecondary)
                Text(entry.createdAt, style: .time)
                    .font(.brandCaption)
                    .foregroundStyle(Brand.inkTertiary)
                Spacer()
                Button(action: toggleFavorite) {
                    Image(systemName: entry.favorite ? "heart.fill" : "heart")
                        .font(.brand(.subheadline))
                        .foregroundStyle(entry.favorite ? Brand.blush : Brand.inkTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        // Small glyph, comfortable tap target.
                        .frame(width: 36, height: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.favorite ? "Unfavorite" : "Favorite")
            }

            Text(entry.text)
                .font(.brandBody)
                .foregroundStyle(Brand.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "waveform")
                    .font(.caption2)
                Text("\(entry.duration, format: .number.precision(.fractionLength(1)))s")
                    .font(.brandCaption)
                Spacer()
                Button {
                    copy()
                    justCopied = true
                } label: {
                    Label(justCopied ? "Copied" : "Copy",
                          systemImage: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.brand(.caption, weight: .medium))
                        .foregroundStyle(justCopied ? Brand.sage : Brand.blush)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy transcript")
                .task(id: justCopied) {
                    guard justCopied else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    justCopied = false
                }
            }
            .foregroundStyle(Brand.inkTertiary)
            .animation(.easeInOut(duration: 0.2), value: justCopied)
        }
        .softCard()
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyHistoryView: View {
    var body: some View {
        HistoryEmptyState(
            systemImage: "text.bubble",
            title: "No transcripts yet",
            message: "Your transcripts will collect here.\nTap the mic on the Record tab to start."
        )
    }
}

private struct EmptyFavoritesView: View {
    var body: some View {
        HistoryEmptyState(
            systemImage: "heart.slash",
            title: "No favorites yet",
            message: "Favorite transcripts to keep them close."
        )
    }
}

private struct HistoryEmptyState: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Brand.blushSoft)
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.brand(.largeTitle, weight: .regular))
                    .foregroundStyle(Brand.blush)
            }
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.brandTitle)
                    .foregroundStyle(Brand.ink)
                Text(message)
                    .font(.brandBody)
                    .foregroundStyle(Brand.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

private struct UndoDeleteBanner: View {
    var undo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text("Transcript deleted")
                .font(.brand(.subheadline, weight: .medium))
                .foregroundStyle(Brand.ink)

            Spacer()

            Button("Undo", action: undo)
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(Brand.blush)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Brand.blushSoft, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
    }
}

#Preview {
    HistoryView()
        .environment(AppSettings())
        .modelContainer(for: TranscriptEntry.self, inMemory: true)
}
