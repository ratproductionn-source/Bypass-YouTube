import SwiftUI

struct ChannelScreen: View {
    let channelId: String

    @Environment(\.dismiss) private var dismiss
    @State private var info: ChannelInfo?
    @State private var videos: [Video] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selection: Video?

    var body: some View {
        NavigationStack {
            content
                .background(Color.black.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("close") { dismiss() }
                    }
                }
                .sheet(item: $selection) { video in
                    WatchScreen(video: video)
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && videos.isEmpty {
            ProgressView("opening channel").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, videos.isEmpty {
            ErrorPane(message: error) { Task { await load() } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(videos) { v in
                        Button {
                            selection = v
                        } label: {
                            VideoRow(video: v)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: info?.avatar) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(info?.title ?? "channel")
                    .font(.headline)
                    .lineLimit(2)
                if let sub = info?.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(videos.count) videos loaded")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let (channel, uploads) = try await InnerTube.channel(channelId)
            info = channel
            videos = uploads
            if uploads.isEmpty { error = "channel has no videos on this tab" }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
