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
                            Text("Looking for Macs on the network…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(browser.macs, id: \.self) { name in
                        Button { select(.service(name: name)) } label: { row(name) }
                    }
                    Button("Connect by IP…") {
                        manualHost = Prefs.lastMacHost ?? ""
                        showManual = true
                    }
                } header: {
                    Text("Macs on the network")
                } footer: {
                    Text("Open PadDeck on the Mac: the PIN is in the keyboard icon in the menu bar. With a USB cable, it connects by itself, no PIN needed.")
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
                        Label("Download PadDeck for Mac", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text("Free, for macOS 12 or later.")
                }
            }
            .navigationTitle("PadDeck")
        }
        .onAppear(perform: appear)
        .onDisappear { browser.stop() }
        .onChange(of: conn.lastDenyReason) { reason in
            if reason == 1, let t = conn.target { askPIN(t, String(localized: "Wrong PIN. Check it in the PadDeck menu on the Mac.")) }
        }
        .alert("PIN for \(pinTarget?.displayName ?? "Mac")", isPresented: $showPin) {
            TextField("0000", text: $pinText).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Connect") {
                if let t = pinTarget { conn.connect(to: t, pin: pinText) }
            }
        } message: {
            Text(pinMessage)
        }
        .alert("Connect by IP", isPresented: $showManual) {
            TextField("192.168.0.10", text: $manualHost)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                let h = manualHost.trimmingCharacters(in: .whitespaces)
                if !h.isEmpty { select(.host(h)) }
            }
        } message: {
            Text("The Mac's address on the network (System Settings › Wi-Fi › Details).")
        }
        .preferredColorScheme(Theme.isLight ? .light : .dark)
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text(Prefs.pin(for: name) != nil ? String(localized: "PIN saved") : String(localized: "Tap to connect"))
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
            if let e = conn.lastError { return String(localized: "\(e) — trying \(name) again…") }
            return String(localized: "Connecting to \(name)…")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askPIN(t, String(localized: "The PIN changed on the Mac. Enter the new PIN.")) }
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
            askPIN(t, String(localized: "Enter the PIN shown in the PadDeck menu on the Mac."))
        }
    }

    private func askPIN(_ t: MacTarget, _ message: String) {
        pinTarget = t
        pinText = ""
        pinMessage = message
        showPin = true
    }
}
