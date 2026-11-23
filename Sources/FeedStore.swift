import Foundation
import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    @Published var videos: [Video] = []
    @Published var query: String = ""
    @Published var loading = false
    @Published var error: String?

    private var inFlight = false

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        loading = true
        error = nil
        defer { inFlight = false; loading = false }

        do {
            let result = isSearching
                ? try await InnerTube.search(query)
                : try await InnerTube.trending()
            videos = result
            if result.isEmpty { error = isSearching ? "no results" : "feed came back empty" }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearSearch() async {
        query = ""
        videos = []
        await refresh()
    }
}
