import SwiftUI

/// First screen: finds Macs running PadDeck (Bonjour), asks for the PIN and connects.
/// Reconnects to the last Mac by itself; the USB cable connects without any of this.
struct ConnectView: View {
    @ObservedObject private var conn = Connection.shared
    @StateObject private var browser = MacBrowser()

    @State private var pinTarget: MacTarget?
    @State private var pinText = ""
    @State private var pinMessage = ""
    @State private var showPin = false
    @State private var showManual = false
    @State private var manualHost = ""
    @State private var triedAuto = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if browser.macs.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Procurando Macs na rede…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(browser.macs, id: \.self) { name in
                        Button { select(.service(name: name)) } label: { row(name) }
                    }
                    Button("Conectar por IP…") {
                        manualHost = Prefs.lastMacHost ?? ""
                        showManual = true
                    }
                } header: {
                    Text("Macs na rede")
                } footer: {
                    Text("Abra o PadDeck no Mac: o PIN aparece no ícone de teclado da barra de menus. Pelo cabo USB, a conexão é automática e sem PIN.")
                }

                if let status = statusText {
                    Section {
                        HStack(spacing: 12) {
                            if conn.state == .connecting { ProgressView() }
                            Text(status)
                        }
                    }
                }

                Section {
                    Link(destination: URL(string: "https://github.com/douugr/paddeck/releases/latest")!) {
                        Label("Baixar o PadDeck para Mac", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text("Grátis, para macOS 12 ou mais novo.")
                }
            }
            .navigationTitle("PadDeck")
        }
        .onAppear(perform: appear)
        .onDisappear { browser.stop() }
        .onChange(of: conn.lastDenyReason) { reason in
            if reason == 1, let t = conn.target { askPIN(t, "PIN incorreto. Confira no menu do PadDeck no Mac.") }
        }
        .alert("PIN de \(pinTarget?.displayName ?? "Mac")", isPresented: $showPin) {
            TextField("0000", text: $pinText).keyboardType(.numberPad)
            Button("Cancelar", role: .cancel) {}
            Button("Conectar") {
                if let t = pinTarget { conn.connect(to: t, pin: pinText) }
            }
        } message: {
            Text(pinMessage)
        }
        .alert("Conectar por IP", isPresented: $showManual) {
            TextField("192.168.0.10", text: $manualHost)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancelar", role: .cancel) {}
            Button("Continuar") {
                let h = manualHost.trimmingCharacters(in: .whitespaces)
                if !h.isEmpty { select(.host(h)) }
            }
        } message: {
            Text("Endereço do Mac na rede (Ajustes do Sistema › Wi-Fi › Detalhes).")
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text(Prefs.pin(for: name) != nil ? "PIN salvo" : "Toque para conectar")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if conn.state == .connecting && conn.target == .service(name: name) { ProgressView() }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String? {
        switch conn.state {
        case .connecting:
            let name = conn.macName ?? "Mac"
            if let e = conn.lastError { return "\(e) — tentando \(name) de novo…" }
            return "Conectando a \(name)…"
        case .idle:
            return conn.lastError
        case .connected:
            return nil
        }
    }

    private func appear() {
        browser.start()
        if conn.state == .idle, conn.lastDenyReason == 1, let t = conn.target {
            // Came back from the main screen because the PIN changed on the Mac.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askPIN(t, "O PIN mudou no Mac. Digite o novo PIN.") }
            return
        }
        guard !triedAuto else { return }
        triedAuto = true
        if let name = Prefs.lastMacName, let pin = Prefs.pin(for: name) {
            conn.connect(to: .service(name: name), pin: pin)
        } else if let host = Prefs.lastMacHost, let pin = Prefs.pin(for: host) {
            conn.connect(to: .host(host), pin: pin)
        }
    }

    private func select(_ t: MacTarget) {
        if let pin = Prefs.pin(for: t.displayName) {
            conn.connect(to: t, pin: pin)
        } else {
            askPIN(t, "Digite o PIN mostrado no menu do PadDeck no Mac.")
        }
    }

    private func askPIN(_ t: MacTarget, _ message: String) {
        pinTarget = t
        pinText = ""
        pinMessage = message
        showPin = true
    }
}
