import SwiftUI

struct SettingsView: View {
    var onDone: () -> Void

    @AppStorage("pointerSpeed") private var pointerSpeed = 1.6
    @AppStorage("scrollSpeed") private var scrollSpeed = 1.5
    @AppStorage("naturalScroll") private var naturalScroll = true
    @AppStorage("tapToClick") private var tapToClick = true
    @AppStorage("tapToDrag") private var tapToDrag = true
    @AppStorage("keyboardOnTop") private var keyboardOnTop = false
    @AppStorage("keyClick") private var keyClick = true
    @AppStorage("keyHaptics") private var keyHaptics = true
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var confirmReset = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Velocidade do cursor")
                        Slider(value: $pointerSpeed, in: 0.5...4)
                    }
                    VStack(alignment: .leading) {
                        Text("Velocidade da rolagem")
                        Slider(value: $scrollSpeed, in: 0.5...4)
                    }
                    Toggle("Rolagem natural", isOn: $naturalScroll)
                    Toggle("Tocar para clicar", isOn: $tapToClick)
                    Toggle("Toque duplo e arraste", isOn: $tapToDrag)
                } header: {
                    Text("Trackpad")
                } footer: {
                    Text("Toque duplo e arraste: toque uma vez e, logo em seguida, encoste e arraste para segurar o clique. Com ele ligado, o clique simples espera um instante.")
                }

                Section("Teclado") {
                    Toggle("Teclado em cima do trackpad", isOn: $keyboardOnTop)
                    Toggle("Som ao tocar nas teclas", isOn: $keyClick)
                    if isPhone { Toggle("Vibração ao tocar nas teclas", isOn: $keyHaptics) }
                }

                Section("Geral") {
                    Toggle("Manter a tela acesa", isOn: $keepAwake)
                }

                Section {
                    Button("Restaurar atalhos padrão", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Para editar um botão, segure-o na tela de atalhos.")
                }

                Section("Sobre") {
                    LabeledContent("Versão", value: version)
                    Link("PadDeck para Mac", destination: URL(string: "https://github.com/douugr/paddeck/releases/latest")!)
                    Link("Código-fonte (MIT)", destination: URL(string: "https://github.com/douugr/paddeck")!)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK", action: onDone) }
            }
            .alert("Restaurar atalhos?", isPresented: $confirmReset) {
                Button("Cancelar", role: .cancel) {}
                Button("Restaurar", role: .destructive) { Deck.shared.resetToDefaults() }
            } message: {
                Text("Todos os botões voltam ao padrão. Os botões que você criou serão apagados.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
