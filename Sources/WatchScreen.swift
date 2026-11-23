import SwiftUI
import UIKit
import Combine
import AVKit

struct WatchScreen: View {
    @State private var current: Video
    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferHLS") private var preferHLS = true
    @AppStorage("maxHeight") private var maxHeight = 720

    @State private var info: PlaybackInfo?
    @State private var player: AVPlayer?
    @State private var currentURL: URL?
    @State private var error: String?
    @State private var loading = true
    @State private var tab: Tab = .upNext

    @State private var related: [Video] = []
    @State private var comments: [Comment] = []
    @State private var commentsToken: String?
    @State private var commentsLoading = false
    @State private var commentsError: String?

    @State private var channelId = ""
    @State private var showChannel = false

    private enum Tab: String, CaseIterable {
        case upNext = "up next"
        case comments = "comments"
        case details = "details"
    }

    init(video: Video) {
        _current = State(initialValue: video)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    stage
                    header
                    streamPicker
                    tabBar
                    tabContent
                }
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: URL(string: "https://youtu.be/\(current.id)")!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task { await load() }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                persistProgress()
            }
            .onDisappear { persistProgress() }
            .sheet(isPresented: $showChannel) {
                ChannelScreen(channelId: channelId)
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
                        Button("safari") {
                            if let u = URL(string: "https://youtu.be/\(current.id)") {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(info?.title.isEmpty == false ? info!.title : current.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(info?.author.isEmpty == false ? info!.author : current.channel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let v = info?.viewsText, !v.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(v).font(.caption).foregroundStyle(.tertiary)
                }
                if let p = info?.published, !p.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(String(p.prefix(10))).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if !channelId.isEmpty {
                Button {
                    showChannel = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                        Text("open channel")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: stream picker

    @ViewBuilder
    private var streamPicker: some View {
        if let info {
            VStack(alignment: .leading, spacing: 8) {
                Text("stream").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let hls = info.hls {
                            chip("hls · auto", active: currentURL == hls) { attach(hls) }
                        }
                        ForEach(info.formats) { f in
                            chip(f.display.lowercased(), active: currentURL == f.url) { attach(f.url) }
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
                .background(active ? Color.white : Color(white: 0.16), in: Capsule())
                .foregroundStyle(active ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: tabs

    private var tabBar: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .upNext: upNextList
        case .comments: commentsList
        case .details: detailsPane
        }
    }

    private var upNextList: some View {
        LazyVStack(spacing: 12) {
            ForEach(related) { v in
                Button {
                    select(v)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AsyncImage(url: v.thumbnail) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color(white: 0.16)
                            }
                        }
                        .frame(width: 150, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Text(v.channel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(v.meta)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var commentsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let commentsError {
                Text(commentsError)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            ForEach(comments) { c in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(c.author)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if !c.published.isEmpty {
                            Text(c.published)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    Text(c.text)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if !c.likes.isEmpty {
                            Label(c.likes, systemImage: "hand.thumbsup")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !c.replies.isEmpty, c.replies != "0" {
                            Label(c.replies, systemImage: "arrowshape.turn.up.left")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if commentsLoading {
                ProgressView().padding(.horizontal, 16)
            } else if commentsToken != nil {
                Button("load more") {
                    Task { await loadMoreComments() }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 16)
            } else if comments.isEmpty {
                Text("no comments on this one")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var detailsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info {
                HStack(spacing: 12) {
                    if !info.viewsText.isEmpty { stat("views", info.viewsText) }
                    if info.duration > 0 { stat("length", Self.clock(info.duration)) }
                    if info.isLive { stat("live", "yes") }
                }
                Text(info.description.isEmpty ? "no description" : info.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("no details").font(.footnote.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    // MARK: logic

    private func load() async {
        loading = true
        error = nil
        related = []
        comments = []
        commentsToken = nil
        commentsError = nil

        do {
            let resolved = try await InnerTube.playback(videoId: current.id)
            info = resolved
            channelId = resolved.channelId
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

        async let relatedTask = InnerTube.related(videoId: current.id)
        async let commentTask = InnerTube.comments(videoId: current.id)

        related = (try? await relatedTask) ?? []
        if let page = try? await commentTask {
            comments = page.comments
            commentsToken = page.token
        } else {
            commentsError = "comments unavailable from this client"
        }
    }

    private func select(_ video: Video) {
        persistProgress()
        player?.pause()
        player = nil
        currentURL = nil
        info = nil
        current = video
        tab = .upNext
        Task { await load() }
    }

    private func loadMoreComments() async {
        guard let token = commentsToken, !commentsLoading else { return }
        commentsLoading = true
        defer { commentsLoading = false }
        do {
            let page = try await InnerTube.comments(continuation: token)
            comments.append(contentsOf: page.comments)
            commentsToken = page.token
        } catch {
            commentsError = error.localizedDescription
            commentsToken = nil
        }
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

        if let resume = History.shared.resumePoint(for: current.id) {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600),
                   toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player = p
    }

    private func persistProgress() {
        guard let player, let item = player.currentItem, item.status == .readyToPlay else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 3 else { return }
        History.shared.record(video: current, info: info, seconds: seconds)
    }

    private func close() {
        persistProgress()
        player?.pause()
        player = nil
        dismiss()
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
