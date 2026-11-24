import SwiftUI

struct SettingsView: View {
    var onDone: () -> Void

    @AppStorage("pointerSpeed") private var pointerSpeed = 1.6
    @AppStorage("scrollSpeed") private var scrollSpeed = 1.5
    @AppStorage("naturalScroll") private var naturalScroll = true
    @AppStorage("inertialScroll") private var inertialScroll = true
    @AppStorage("scrollStrip") private var scrollStrip = true
    @AppStorage("scrollStripLeft") private var scrollStripLeft = false
    @AppStorage("tapToClick") private var tapToClick = true
    @AppStorage("tapToDrag") private var tapToDrag = true
    @AppStorage("keyboardOnTop") private var keyboardOnTop = false
    @AppStorage("keyClick") private var keyClick = true
    @AppStorage("keyHaptics") private var keyHaptics = true
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("theme") private var theme = "dark"
    @State private var confirmReset = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Follows the picker right away, so Settings previews the profile while it is open.
    private var palette: Palette { Theme.palette(id: theme) }

    private var themeLabel: String {
        let p = Theme.palette(id: theme)
        return p.line == .paddeck ? p.localizedName : "\(p.line.rawValue) · \(p.localizedName)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Pointer speed")
                        Slider(value: $pointerSpeed, in: 0.5...4)
                    }
                    VStack(alignment: .leading) {
                        Text("Scroll speed")
                        Slider(value: $scrollSpeed, in: 0.5...4)
                    }
                    Toggle("Natural scrolling", isOn: $naturalScroll)
                    Toggle("Momentum scrolling", isOn: $inertialScroll)
                    Toggle("Scroll strip", isOn: $scrollStrip)
                    if scrollStrip { Toggle("Strip on the left", isOn: $scrollStripLeft) }
                    Toggle("Tap to click", isOn: $tapToClick)
                    Toggle("Double-tap and drag", isOn: $tapToDrag)
                } header: {
                    Text("Trackpad")
                } footer: {
                    Text("Momentum scrolling: swipe two fingers quickly and let go to keep the page scrolling; touch the trackpad to stop.\n\nScroll strip: slide one finger along the edge of the trackpad to scroll.\n\nDouble-tap and drag: tap once, then touch again and drag to hold the click. With it on, a single click waits a moment.")
                }
                .themedRows(palette)

                Section {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        HStack(spacing: 14) {
                            ThemeSwatch(palette: Theme.palette(id: theme))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Colors")
                                Text(themeLabel).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Match PadDeck to the color of your Mac.")
                }
                .themedRows(palette)

                Section("Keyboard") {
                    Toggle("Keyboard above the trackpad", isOn: $keyboardOnTop)
                    Toggle("Key click sound", isOn: $keyClick)
                    if isPhone { Toggle("Key haptics", isOn: $keyHaptics) }
                }
                .themedRows(palette)

                Section("General") {
                    Toggle("Keep the screen on", isOn: $keepAwake)
                }
                .themedRows(palette)

                Section {
                    Button("Restore default shortcuts", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("To edit a button, touch and hold it on the Shortcuts screen.")
                }
                .themedRows(palette)

                Section("About") {
                    LabeledContent("Version", value: version)
                    Link("PadDeck for Mac", destination: URL(string: "https://github.com/douugr/paddeck/releases/latest")!)
                    Link("Source code (MIT)", destination: URL(string: "https://github.com/douugr/paddeck")!)
                }
                .themedRows(palette)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .themedList(palette)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK", action: onDone) }
            }
            .alert("Restore shortcuts?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) { Deck.shared.resetToDefaults() }
            } message: {
                Text("All buttons go back to the defaults. Buttons you created will be deleted.")
            }
        }
    }
}
