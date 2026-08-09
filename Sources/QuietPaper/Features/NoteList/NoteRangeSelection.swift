import Foundation

struct NoteRangeSelection: Equatable, Sendable {
    private(set) var selectedIDs = Set<UUID>()
    private(set) var anchorID: UUID?

    mutating func select(
        _ targetID: UUID,
        orderedIDs: [UUID],
        extendingRange: Bool,
        fallbackAnchorID: UUID? = nil
    ) {
        guard extendingRange,
              let anchorID = anchorID ?? fallbackAnchorID,
              let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID) else {
            selectedIDs.removeAll()
            anchorID = targetID
            return
        }

        self.anchorID = anchorID
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(bounds.map { orderedIDs[$0] })
    }

    mutating func retainValidIDs(_ validIDs: Set<UUID>) {
        selectedIDs.formIntersection(validIDs)
        if selectedIDs.count < 2 { selectedIDs.removeAll() }
        if let anchorID, !validIDs.contains(anchorID) { self.anchorID = nil }
    }

    func resolvedActionIDs(for targetID: UUID, orderedIDs: [UUID]) -> [UUID] {
        guard selectedIDs.count >= 2, selectedIDs.contains(targetID) else { return [targetID] }
        return orderedIDs.filter(selectedIDs.contains)
    }

    mutating func reset() {
        selectedIDs.removeAll()
        anchorID = nil
    }
}
