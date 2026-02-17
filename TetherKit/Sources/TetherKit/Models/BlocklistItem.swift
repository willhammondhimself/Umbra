import Foundation
import GRDB

public struct BlocklistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var bundleId: String?
    public var domain: String?
    public var displayName: String
    public var blockMode: BlockMode
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
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

    public enum BlockMode: Int, Codable, CaseIterable, Sendable {
        case softWarn = 0
        case hardBlock = 1
        case timedLock = 2

        public var label: String {
            switch self {
            case .softWarn: "Soft Warn"
            case .hardBlock: "Hard Block"
            case .timedLock: "Timed Lock"
            }
        }

        public var description: String {
            switch self {
            case .softWarn: "Show overlay, allow continue"
            case .hardBlock: "Prevent use, require override"
            case .timedLock: "Block with 10s cooldown"
            }
        }
    }

    public var isAppBlock: Bool { bundleId != nil }
    public var isWebBlock: Bool { domain != nil }
}

// MARK: - GRDB

extension BlocklistItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "blocklist_items"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
