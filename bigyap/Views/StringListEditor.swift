import SwiftUI

/// Reusable add/delete list editor, used for both the custom vocabulary and the
/// filler-word list.
struct StringListEditor: View {
    let title: String
    let prompt: String
    let footer: String
    @Binding var items: [String]
    var resetDefaults: [String]? = nil

    @State private var newItem = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        newItem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.sm) {
                    TextField(prompt, text: $newItem)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .noAutocapitalization()
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(trimmed.isEmpty ? Brand.inkTertiary : Brand.blush)
                    .disabled(trimmed.isEmpty)
                }
            } footer: {
                Text(footer)
            }

            if items.isEmpty {
                Section {
                    Text("Nothing added yet.")
                        .foregroundStyle(Brand.inkSecondary)
                }
            } else {
                Section("\(items.count) \(items.count == 1 ? "entry" : "entries")") {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.brandBody)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.canvas)
        .navigationTitle(title)
        .inlineNavigationTitle()
        .tint(Brand.blush)
        .toolbar {
            if let resetDefaults, items != resetDefaults {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        items = resetDefaults
                        Haptics.tap()
                    }
                }
            }
        }
    }

    private func add() {
        let value = trimmed
        guard !value.isEmpty,
              !items.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            newItem = ""
            return
        }
        items.append(value)
        newItem = ""
        Haptics.tap()
    }
}
