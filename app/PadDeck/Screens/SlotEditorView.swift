import SwiftUI

/// Edits one deck button.
struct SlotEditorView: View {
    enum Result { case cancel, save(Slot), delete }

    private let isNew: Bool
    private let onDone: (Result) -> Void

    @State private var title: String
    @State private var action: Slot.Action
    @State private var value: String
    @State private var media: MediaKey
    @State private var color: Int

    init(slot: Slot?, onDone: @escaping (Result) -> Void) {
        isNew = slot == nil
        self.onDone = onDone
        _title = State(initialValue: slot?.title ?? "")
        _action = State(initialValue: slot?.action ?? .shortcut)
        _value = State(initialValue: slot?.action == .media ? "" : (slot?.value ?? ""))
        _media = State(initialValue: slot.flatMap { MediaKey(rawValue: $0.value) } ?? .play)
        _color = State(initialValue: slot?.color ?? 1)
    }

    private var current: Slot {
        let v = action == .media ? media.rawValue : value
        var t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            switch action {
            case .shortcut: t = Keys.prettyShortcut(v)
            case .media: t = media.label
            default: t = v
            }
        }
        return Slot(title: t, action: action, value: v, color: color)
    }

    private var hint: (String, Color) {
        switch action {
        case .shortcut:
            if value.isEmpty { return (String(localized: "Modifiers: cmd, shift, ctrl, opt, fn. Keys: letters, numbers, space, tab, return, esc, delete, up/down/left/right, f1–f12."), .secondary) }
            if Keys.parseShortcut(value) != nil { return (String(localized: "Sends \(Keys.prettyShortcut(value))"), .green) }
            return (String(localized: "Shortcut not recognized. E.g. cmd+shift+4, ctrl+up, f11"), .red)
        case .text: return (String(localized: "Typed on the Mac as text (accents work)."), .secondary)
        case .open: return (String(localized: "App name (as shown in Applications), bundle ID, path or web address."), .secondary)
        case .media: return (String(localized: "The Mac's media keys."), .secondary)
        }
    }

    private var placeholder: String {
        switch action {
        case .shortcut: return "cmd+shift+4"
        case .text: return String(localized: "Text to type")
        case .open: return String(localized: "Safari, com.apple.Music or https://…")
        case .media: return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("E.g. Screenshot", text: $title)
                }
                .themedRows()
                Section {
                    Picker("Action", selection: $action) {
                        ForEach(Slot.Action.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if action == .media {
                        Picker("Key", selection: $media) {
                            ForEach(MediaKey.allCases) { m in Label(m.label, systemImage: m.symbol).tag(m) }
                        }
                    } else {
                        TextField(placeholder, text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Action")
                } footer: {
                    Text(hint.0).foregroundStyle(hint.1)
                }
                .themedRows()
                Section("Color") {
                    HStack(spacing: 14) {
                        ForEach(Theme.deckColors.indices, id: \.self) { i in
                            Circle()
                                .fill(Color(Theme.deckColors[i]))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == i ? 3 : 0))
                                .onTapGesture { color = i }
                                .accessibilityAddTraits(color == i ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .themedRows()
                Section {
                    Button("Try on the Mac") { current.perform() }
                        .disabled(!current.isValid)
                    if !isNew {
                        Button("Delete button", role: .destructive) { onDone(.delete) }
                    }
                }
                .themedRows()
            }
            .navigationTitle(isNew ? String(localized: "New button") : String(localized: "Edit button"))
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(.cancel) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onDone(.save(current)) }.disabled(!current.isValid)
                }
            }
        }
    }
}
