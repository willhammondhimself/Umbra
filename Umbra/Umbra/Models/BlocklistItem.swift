import Foundation
import GRDB

struct BlocklistItem: Identifiable, Codable, Equatable {
    var id: Int64?
    var bundleId: String?
    var domain: String?
    var displayName: String
    var blockMode: BlockMode
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: Int64? = nil,
        bundleId: String? = nil,
        domain: String? = nil,
        displayName: String,
        blockMode: BlockMode = .softWarn,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bundleId = bundleId
        self.domain = domain
        self.displayName = displayName
        self.blockMode = blockMode
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    enum BlockMode: Int, Codable, CaseIterable {
        case softWarn = 0
        case hardBlock = 1
        case timedLock = 2

        var label: String {
            switch self {
            case .softWarn: "Soft Warn"
            case .hardBlock: "Hard Block"
            case .timedLock: "Timed Lock"
            }
        }

        var description: String {
            switch self {
            case .softWarn: "Show overlay, allow continue"
            case .hardBlock: "Prevent use, require override"
            case .timedLock: "Block with 10s cooldown"
            }
        }
    }

    var isAppBlock: Bool { bundleId != nil }
    var isWebBlock: Bool { domain != nil }
}

// MARK: - GRDB

extension BlocklistItem: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "blocklist_items"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
