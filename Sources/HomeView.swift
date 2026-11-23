import SwiftUI

struct HomeView: View {
    @StateObject private var store = FeedStore()
    @State private var selection: Video?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(store.isSearching ? "results" : "tubefree")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "search youtube")
                .onSubmit(of: .search) { Task { await store.refresh() } }
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
            PlayerScreen(video: video)
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
                LazyVStack(spacing: 16) {
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
