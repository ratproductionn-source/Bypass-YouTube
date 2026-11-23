import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = History.shared
    @AppStorage("preferHLS") private var preferHLS = true
    @AppStorage("maxHeight") private var maxHeight = 720

    private let heights = [360, 480, 720, 1080]

    var body: some View {
        NavigationStack {
            Form {
                Section("playback") {
                    Toggle("prefer hls (auto quality)", isOn: $preferHLS)
                        .tint(.green)

                    Picker("max progressive height", selection: $maxHeight) {
                        ForEach(heights, id: \.self) { h in
                            Text("\(h)p").tag(h)
                        }
                    }
                    .disabled(preferHLS)
                }

                Section("history") {
                    row("entries", "\(history.entries.count)")
                    Button("clear watch history", role: .destructive) {
                        history.clear()
                    }
                }

                Section("how it works") {
                    Text("The app talks to YouTube's InnerTube API directly and hands the resolved stream to AVPlayer. The watch page is never loaded, so the ad machinery is never instantiated — there is nothing to skip.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("No login, no cookies, no tracking identifier. Requests are ephemeral; watch history is stored locally and never leaves the device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("build") {
                    row("bundle", Bundle.main.bundleIdentifier ?? "-")
                    row("version", (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "-")
                    row("clients", "IOS · ANDROID · ANDROID_VR · WEB_EMBEDDED")
                }
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.footnote.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.footnote.monospaced())
        }
    }
}
