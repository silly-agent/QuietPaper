import Foundation

enum EditorFindDirection {
    case next
    case previous
}

enum EditorFindMatcher {
    static func ranges(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var searchRange = fullRange
        var matches: [NSRange] = []

        while searchRange.length > 0 {
            let match = source.range(
                of: query,
                options: [.caseInsensitive, .widthInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound else { break }
            matches.append(match)

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(
                location: nextLocation,
                length: NSMaxRange(fullRange) - nextLocation
            )
        }

        return matches
    }
}

enum EditorFindNavigator {
    static func movedIndex(
        from currentIndex: Int?,
        matchCount: Int,
        direction: EditorFindDirection
    ) -> Int? {
        guard matchCount > 0 else { return nil }

        switch direction {
        case .next:
            guard let currentIndex else { return 0 }
            return (currentIndex + 1) % matchCount
        case .previous:
            guard let currentIndex else { return matchCount - 1 }
            return (currentIndex - 1 + matchCount) % matchCount
        }
    }
}

struct EditorFindSelection: Equatable {
    private(set) var activeIndex: Int?
    private(set) var matchCount = 0

    mutating func refresh(matchCount: Int, selectFirst: Bool) {
        self.matchCount = max(0, matchCount)
        guard self.matchCount > 0 else {
            activeIndex = nil
            return
        }

        if selectFirst || activeIndex == nil {
            activeIndex = 0
        } else if let activeIndex, activeIndex >= self.matchCount {
            self.activeIndex = self.matchCount - 1
        }
    }

    mutating func move(_ direction: EditorFindDirection, matchCount: Int) {
        self.matchCount = max(0, matchCount)
        activeIndex = EditorFindNavigator.movedIndex(
            from: activeIndex,
            matchCount: self.matchCount,
            direction: direction
        )
    }

    mutating func reset() {
        activeIndex = nil
        matchCount = 0
    }
}

struct PreviewSearchUnit: Equatable, Identifiable {
    let id: Int
    let text: String
}

struct PreviewSearchMatch: Equatable {
    let unitID: Int
    let range: NSRange
}

struct PreviewSearchIndex {
    let units: [PreviewSearchUnit]
    let unitIDsByBlock: [[Int]]

    init(blocks: [MarkdownBlock]) {
        var units: [PreviewSearchUnit] = []
        var unitIDsByBlock: [[Int]] = []

        func append(_ text: String, to blockUnitIDs: inout [Int]) {
            let id = units.count
            units.append(PreviewSearchUnit(id: id, text: text))
            blockUnitIDs.append(id)
        }

        for block in blocks {
            var blockUnitIDs: [Int] = []
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text):
                append(Self.visibleInlineText(text), to: &blockUnitIDs)
            case .bullets(let items):
                for item in items {
                    append(Self.visibleInlineText(item), to: &blockUnitIDs)
                }
            case .code(_, let content):
                append(content, to: &blockUnitIDs)
            case .table(let table):
                for cell in table.headers + table.rows.flatMap({ $0 }) {
                    append(Self.visibleInlineText(cell), to: &blockUnitIDs)
                }
            case .image(let alt, _):
                if !alt.isEmpty {
                    append(Self.visibleInlineText(alt), to: &blockUnitIDs)
                }
            case .divider:
                break
            }
            unitIDsByBlock.append(blockUnitIDs)
        }

        self.units = units
        self.unitIDsByBlock = unitIDsByBlock
    }

    static func units(from blocks: [MarkdownBlock]) -> [PreviewSearchUnit] {
        PreviewSearchIndex(blocks: blocks).units
    }

    static func matches(in units: [PreviewSearchUnit], query: String) -> [PreviewSearchMatch] {
        units.flatMap { unit in
            EditorFindMatcher.ranges(in: unit.text, query: query).map {
                PreviewSearchMatch(unitID: unit.id, range: $0)
            }
        }
    }

    func matches(query: String) -> [PreviewSearchMatch] {
        Self.matches(in: units, query: query)
    }

    func match(at globalIndex: Int?, query: String) -> PreviewSearchMatch? {
        guard let globalIndex else { return nil }
        let matches = matches(query: query)
        guard matches.indices.contains(globalIndex) else { return nil }
        return matches[globalIndex]
    }

    func unitIDs(forBlockAt index: Int) -> [Int] {
        guard unitIDsByBlock.indices.contains(index) else { return [] }
        return unitIDsByBlock[index]
    }

    private static func visibleInlineText(_ source: String) -> String {
        String(MarkdownInlineText.attributed(source).characters)
    }
}
