import Foundation
import Observation
import FirebaseFirestore

struct HistoryPage: Sendable {
    let entries: [FondMessage]
    let hasMore: Bool
}

@MainActor
protocol HistoryProviding: AnyObject {
    func reset()
    func nextPage(connectionId: String) async throws -> HistoryPage
}

@MainActor
final class FirebaseHistoryProvider: HistoryProviding {
    private var lastDocument: DocumentSnapshot?

    func reset() {
        lastDocument = nil
    }

    func nextPage(connectionId: String) async throws -> HistoryPage {
        let result = try await FirebaseManager.shared.fetchHistory(
            connectionId: connectionId,
            startAfter: lastDocument
        )
        lastDocument = result.lastDocument
        return HistoryPage(
            entries: result.entries,
            hasMore: result.lastDocument != nil
        )
    }
}

@MainActor
@Observable
final class TogetherThreadStore {
    private(set) var moments: [TogetherMoment] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?

    private let provider: any HistoryProviding
    private let myUid: String
    private let decrypt: (String) -> String?
    private let promptText: (String) -> String?
    private var entriesByID: [String: FondMessage] = [:]

    init(
        provider: any HistoryProviding,
        myUid: String,
        decrypt: @escaping (String) -> String?,
        promptText: @escaping (String) -> String?
    ) {
        self.provider = provider
        self.myUid = myUid
        self.decrypt = decrypt
        self.promptText = promptText
    }

    func loadInitial(connectionId: String) async {
        guard !isLoading else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        entriesByID.removeAll(keepingCapacity: true)
        moments = []
        hasMore = true
        provider.reset()
        defer { isLoading = false }

        do {
            let page = try await provider.nextPage(connectionId: connectionId)
            merge(page.entries)
            hasMore = page.hasMore
        } catch {
            hasMore = false
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(connectionId: String) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let page = try await provider.nextPage(connectionId: connectionId)
            merge(page.entries)
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(_ entries: [FondMessage]) {
        for entry in entries {
            if entriesByID[entry.id] == nil {
                entriesByID[entry.id] = entry
            }
        }
        moments = TogetherMomentBuilder.build(
            entries: Array(entriesByID.values),
            myUid: myUid,
            decrypt: decrypt,
            promptText: promptText
        )
    }
}
