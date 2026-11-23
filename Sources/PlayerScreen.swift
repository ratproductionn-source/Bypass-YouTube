import SwiftUI
import UIKit
import AVKit

struct PlayerScreen: View {
    let video: Video

    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferHLS") private var preferHLS = true
    @AppStorage("maxHeight") private var maxHeight = 720

    @State private var info: PlaybackInfo?
    @State private var player: AVPlayer?
    @State private var currentURL: URL?
    @State private var error: String?
    @State private var loading = true
    @State private var related: [Video] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    stage
                    header
                    picker
                    relatedStrip
                }
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: URL(string: "https://youtu.be/\(video.id)")!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task { await load() }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    // MARK: stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            Color.black
            if let player {
                PlayerContainer(player: player)
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("resolving stream").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .light))
                    Text(error ?? "no playable stream")
                        .font(.footnote.monospaced())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    HStack(spacing: 10) {
                        Button("retry") { Task { await load() } }
                            .buttonStyle(.bordered)
                        Button("open in safari") {
                            if let u = URL(string: "https://youtu.be/\(video.id)") {
                                UIApplication.shared.open(u)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(.black)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info?.title.isEmpty == false ? info!.title : video.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(info?.author.isEmpty == false ? info!.author : video.channel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let dur = info?.duration, dur > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text(Self.clock(dur)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if !video.meta.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(video.meta).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: picker

    @ViewBuilder
    private var picker: some View {
        if let info {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("stream").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    if let hls = info.hls {
                        chip("hls · auto", active: currentURL == hls) {
                            attach(hls)
                        }
                    }
                    ForEach(info.formats.prefix(4)) { f in
                        chip(f.display.lowercased(), active: currentURL == f.url) {
                            attach(f.url)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color.white : Color(white: 0.16),
                            in: Capsule())
                .foregroundStyle(active ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: related

    @ViewBuilder
    private var relatedStrip: some View {
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("up next").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(related.prefix(12)) { v in
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: v.thumbnail) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color(white: 0.16)
                                    }
                                }
                                .frame(width: 170, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(v.title)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .frame(width: 170, alignment: .leading)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: logic

    private func load() async {
        loading = true
        error = nil
        do {
            let resolved = try await InnerTube.playback(videoId: video.id)
            info = resolved
            guard let url = pick(resolved) else {
                error = "no playable stream for this video"
                loading = false
                return
            }
            attach(url)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false

        related = (try? await InnerTube.related(videoId: video.id)) ?? []
    }

    private func pick(_ info: PlaybackInfo) -> URL? {
        if preferHLS, let hls = info.hls { return hls }
        let sorted = info.formats.sorted { $0.height > $1.height }
        if let capped = sorted.first(where: { $0.height <= maxHeight }) { return capped.url }
        return sorted.first?.url ?? info.hls
    }

    private func attach(_ url: URL) {
        if url == currentURL, player != nil { return }
        currentURL = url
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        let p = player ?? AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        p.replaceCurrentItem(with: item)
        p.play()
        player = p
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// Native transport controls, PiP, AirPlay and fullscreen for free.
struct PlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = false
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
