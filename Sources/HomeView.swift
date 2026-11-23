import SwiftUI

struct HomeView: View {
    @StateObject private var store = FeedStore()
    @ObservedObject private var history = History.shared

    @State private var selection: Video?
    @State private var showSettings = false
    @State private var suggestions: [String] = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(store.isSearching ? "results" : "tubefree")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $store.query,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "search youtube")
                .searchSuggestions {
                    ForEach(suggestions, id: \.self) { s in
                        Text(s).searchCompletion(s)
                    }
                }
                .onSubmit(of: .search) { Task { await store.refresh() } }
                .task(id: store.query) {
                    let q = store.query
                    guard q.count >= 2, !q.isEmpty else { suggestions = []; return }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    suggestions = (try? await InnerTube.suggest(q)) ?? []
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if store.isSearching {
                            Button {
                                Task { await store.clearSearch() }
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.loading)

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
        }
        .sheet(item: $selection) { video in
            WatchScreen(video: video)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            if store.videos.isEmpty { await store.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.videos.isEmpty && store.loading {
            ProgressView("pulling feed").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = store.error, store.videos.isEmpty {
            ErrorPane(message: message) {
                Task { await store.refresh() }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !store.isSearching { continueWatching }

                    ForEach(store.videos) { video in
                        Button {
                            selection = video
                        } label: {
                            VideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .refreshable { await store.refresh() }
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !history.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("continue watching")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(history.entries.prefix(12)) { entry in
                            Button {
                                selection = Video(id: entry.id,
                                                   title: entry.title,
                                                   channel: entry.channel,
                                                   thumbnail: entry.thumbnail.flatMap(URL.init(string:)),
                                                   duration: "",
                                                   meta: "")
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ZStack(alignment: .bottom) {
                                        AsyncImage(url: entry.thumbnail.flatMap(URL.init(string:))) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Color(white: 0.16)
                                            }
                                        }
                                        .frame(width: 176, height: 99)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Color.red)
                                                .frame(width: geo.size.width * entry.progress, height: 3)
                                                .frame(maxHeight: .infinity, alignment: .bottom)
                                        }
                                        .frame(width: 176, height: 99)
                                    }

                                    Text(entry.title)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .frame(width: 176, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

struct ErrorPane: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Button("retry", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
