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
            if value.isEmpty { return ("Modificadores: cmd, shift, ctrl, opt, fn. Teclas: letras, números, space, tab, return, esc, delete, up/down/left/right, f1–f12.", .secondary) }
            if Keys.parseShortcut(value) != nil { return ("Envia \(Keys.prettyShortcut(value))", .green) }
            return ("Atalho não reconhecido. Ex.: cmd+shift+4, ctrl+up, f11", .red)
        case .text: return ("Digitado no Mac como texto (acentos funcionam).", .secondary)
        case .open: return ("Nome do app (como aparece em Aplicativos), bundle id, caminho ou endereço web.", .secondary)
        case .media: return ("Teclas de mídia do Mac.", .secondary)
        }
    }

    private var placeholder: String {
        switch action {
        case .shortcut: return "cmd+shift+4"
        case .text: return "Texto que será digitado"
        case .open: return "Safari, com.apple.Music ou https://…"
        case .media: return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Ex.: Captura de tela", text: $title)
                }
                Section {
                    Picker("Ação", selection: $action) {
                        ForEach(Slot.Action.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if action == .media {
                        Picker("Tecla", selection: $media) {
                            ForEach(MediaKey.allCases) { m in Label(m.label, systemImage: m.symbol).tag(m) }
                        }
                    } else {
                        TextField(placeholder, text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Ação")
                } footer: {
                    Text(hint.0).foregroundStyle(hint.1)
                }
                Section("Cor") {
                    HStack(spacing: 14) {
                        ForEach(Theme.deckColors.indices, id: \.self) { i in
                            Circle()
                                .fill(Color(Theme.deckColors[i]))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(Color.white, lineWidth: color == i ? 3 : 0))
                                .onTapGesture { color = i }
                                .accessibilityAddTraits(color == i ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Testar no Mac") { current.perform() }
                        .disabled(!current.isValid)
                    if !isNew {
                        Button("Apagar botão", role: .destructive) { onDone(.delete) }
                    }
                }
            }
            .navigationTitle(isNew ? "Novo botão" : "Editar botão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onDone(.cancel) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { onDone(.save(current)) }.disabled(!current.isValid)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
