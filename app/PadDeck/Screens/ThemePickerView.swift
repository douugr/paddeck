import SwiftUI

/// Color profiles grouped by Mac line, each with a small preview of the trackpad and keys.
struct ThemePickerView: View {
    @AppStorage("theme") private var theme = "dark"
    private var palette: Palette { Theme.palette(id: theme) }

    var body: some View {
        List {
            ForEach(Palette.Line.allCases, id: \.self) { line in
                Section(line.rawValue) {
                    ForEach(Theme.all.filter { $0.line == line }) { p in
                        Button { theme = p.id } label: { row(p) }
                            .foregroundStyle(Color(palette.text))
                    }
                }
                .themedRows(palette)
            }
            Section {
            } footer: {
                Text("The new colors are applied when you close Settings.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .themedList(palette)
    }

    private func row(_ p: Palette) -> some View {
        HStack(spacing: 14) {
            ThemeSwatch(palette: p)
            Text(p.localizedName)
            Spacer()
            if theme == p.id {
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(theme == p.id ? .isSelected : [])
    }
}

/// Miniature of the main screen: background, trackpad and a row of keys.
struct ThemeSwatch: View {
    let palette: Palette

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(palette.background))
            .frame(width: 58, height: 40)
            .overlay(
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(palette.surface))
                        .frame(height: 14)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(i == 4 ? palette.accent : palette.key))
                        }
                    }
                    .frame(height: 9)
                }
                .padding(5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
