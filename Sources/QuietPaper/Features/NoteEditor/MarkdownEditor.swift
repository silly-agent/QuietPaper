import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MarkdownEditorCommand {
    case heading(level: Int?)
    case bullet
    case quote
    case code
    case table(columns: Int, dataRows: Int)
    case formatJSON
}

enum MarkdownTableTemplate {
    static func make(columns: Int, dataRows: Int) -> String {
        let safeColumns = min(max(columns, 2), 12)
        let safeDataRows = min(max(dataRows, 1), 30)
        let headers = (1...safeColumns).map { "列 \($0)" }
        let separators = Array(repeating: "---", count: safeColumns)
        let rows = (1...safeDataRows).map { row in
            (1...safeColumns).map { column in "内容 \(row)-\(column)" }
        }
        return ([headers, separators] + rows)
            .map { "| " + $0.joined(separator: " | ") + " |" }
            .joined(separator: "\n")
    }
}

@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: PastingTextView?
    private var activeDocumentID: UUID?
    private var viewportSnapshot: MarkdownEditorViewportSnapshot?

    func attach(
        _ textView: PastingTextView,
        documentID: UUID?,
        replacingCurrentEditor: Bool = false
    ) {
        guard replacingCurrentEditor || self.textView == nil || self.textView === textView else { return }
        self.textView = textView
        activeDocumentID = documentID
    }

    func captureViewport() {
        guard let textView else { return }
        viewportSnapshot = textView.viewportSnapshot(documentID: activeDocumentID)
    }

    func restoreViewport(in textView: PastingTextView, documentID: UUID?) {
        guard self.textView === textView,
              let viewportSnapshot,
              viewportSnapshot.documentID == documentID else { return }
        textView.restoreViewport(viewportSnapshot)
    }

    @discardableResult
    func apply(_ command: MarkdownEditorCommand) -> Bool {
        textView?.apply(command) ?? false
    }

    @discardableResult
    func insertImage(_ image: NSImage, markdown: String) -> Bool {
        textView?.insertImage(image, markdown: markdown) ?? false
    }

    @discardableResult
    func insertTable(columns: Int, dataRows: Int) -> Bool {
        textView?.insertTable(columns: columns, dataRows: dataRows) ?? false
    }

    func findRanges(for query: String) -> [NSRange] {
        guard let textView else { return [] }
        return EditorFindMatcher.ranges(in: textView.string, query: query)
    }

    @discardableResult
    func revealFindMatch(_ range: NSRange) -> Bool {
        guard let textView else { return false }
        return textView.revealFindMatch(range)
    }

}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let onPasteImage: (NSImage) -> String?
    let resolveImage: (String) -> NSImage?
    var documentID: UUID? = nil
    var controller: MarkdownEditorController? = nil
    var showsScrollIndicators = true
    var onFind: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = showsScrollIndicators
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let initialSize = NSSize(
            width: max(scroll.contentSize.width, 640),
            height: max(scroll.contentSize.height, 420)
        )
        let textView = PastingTextView(frame: NSRect(origin: .zero, size: initialSize))
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15.5)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: initialSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: initialSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.typingAttributes = PastingTextView.defaultTextAttributes
        textView.setMarkdown(text, resolveImage: resolveImage)
        textView.onPasteImage = onPasteImage
        textView.resolveImage = resolveImage
        textView.onFind = onFind
        textView.registerForDraggedTypes([.fileURL, .tiff, .png])
        scroll.documentView = textView
        controller?.attach(textView, documentID: documentID, replacingCurrentEditor: true)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            controller?.restoreViewport(in: textView, documentID: documentID)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PastingTextView else { return }
        context.coordinator.parent = self
        controller?.attach(textView, documentID: documentID)
        scroll.hasVerticalScroller = showsScrollIndicators
        textView.onPasteImage = onPasteImage
        textView.resolveImage = resolveImage
        textView.onFind = onFind
        textView.minSize = NSSize(
            width: 0,
            height: max(scroll.contentSize.height, 1)
        )
        if context.coordinator.synchronizer.shouldApplyExternalText(
            text,
            documentID: documentID,
            currentEditorText: { textView.markdownString },
            hasMarkedText: textView.hasMarkedText()
        ) {
            let selection = textView.selectedRange()
            textView.setMarkdown(text, resolveImage: resolveImage)
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.onFocusChange(false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var synchronizer: EditorTextSynchronizer

        init(parent: MarkdownEditor) {
            self.parent = parent
            synchronizer = EditorTextSynchronizer(documentID: parent.documentID, externalText: parent.text)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PastingTextView else { return }
            let markdown = textView.markdownString
            synchronizer.editorDidChange(to: markdown)
            parent.text = markdown
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }
    }
}

struct MarkdownEditorViewportSnapshot: Equatable {
    let documentID: UUID?
    let selection: NSRange
    let topVisibleCharacterIndex: Int?
    let verticalOffset: CGFloat

    func clampedSelection(textLength: Int) -> NSRange {
        let location = min(selection.location, textLength)
        return NSRange(
            location: location,
            length: min(selection.length, textLength - location)
        )
    }
}

struct EditorTextSynchronizer {
    private var documentID: UUID?
    private var pendingEditorText: String?
    private var lastObservedExternalText: String

    init(documentID: UUID?, externalText: String) {
        self.documentID = documentID
        lastObservedExternalText = externalText
    }

    mutating func editorDidChange(to text: String) {
        pendingEditorText = text
    }

    mutating func shouldApplyExternalText(
        _ externalText: String,
        documentID newDocumentID: UUID?,
        currentEditorText: () -> String,
        hasMarkedText: Bool
    ) -> Bool {
        if newDocumentID != documentID {
            documentID = newDocumentID
            pendingEditorText = nil
            lastObservedExternalText = externalText
            return externalText != currentEditorText()
        }

        guard externalText != lastObservedExternalText else { return false }

        if let pendingEditorText {
            if externalText == pendingEditorText {
                self.pendingEditorText = nil
                lastObservedExternalText = externalText
            }
            return false
        }

        guard !hasMarkedText else { return false }
        lastObservedExternalText = externalText
        return externalText != currentEditorText()
    }
}

final class PastingTextView: NSTextView {
    static let defaultTextAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15.5),
        .foregroundColor: NSColor.labelColor,
        .kern: NSNumber(1.6),
        .paragraphStyle: defaultParagraphStyle
    ]

    private static var defaultParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 3
        return style
    }

    private static let fencedCodeRegex = try! NSRegularExpression(
        pattern: #"^```[^\r\n]*\r?\n.*?^```[ \t]*$"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    private static let fencedJSONRegex = try! NSRegularExpression(
        pattern: #"^```[ \t]*json[ \t]*\r?\n.*?^```[ \t]*$"#,
        options: [.caseInsensitive, .anchorsMatchLines, .dotMatchesLineSeparators]
    )

    var onPasteImage: ((NSImage) -> String?)?
    var resolveImage: ((String) -> NSImage?)?
    var onFind: (() -> Void)?

    var markdownString: String {
        let source = attributedString()
        var markdown = ""
        var location = 0
        while location < source.length {
            var range = NSRange(location: 0, length: 0)
            if let marker = source.attribute(
                .quietPaperImageMarkdown,
                at: location,
                effectiveRange: &range
            ) as? String,
               source.attribute(.attachment, at: location, effectiveRange: nil) is NSTextAttachment {
                markdown += marker
                location = NSMaxRange(range)
            } else {
                source.attribute(.quietPaperImageMarkdown, at: location, effectiveRange: &range)
                markdown += (source.string as NSString).substring(with: range)
                location = NSMaxRange(range)
            }
        }
        return MarkdownImageSyntax.normalized(markdown)
    }

    func viewportSnapshot(documentID: UUID?) -> MarkdownEditorViewportSnapshot {
        guard let layoutManager,
              let textContainer,
              layoutManager.numberOfGlyphs > 0 else {
            return MarkdownEditorViewportSnapshot(
                documentID: documentID,
                selection: selectedRange(),
                topVisibleCharacterIndex: nil,
                verticalOffset: 0
            )
        }

        layoutManager.ensureLayout(for: textContainer)
        let visibleRect = enclosingScrollView?.documentVisibleRect ?? visibleRect
        let containerOrigin = textContainerOrigin
        let point = NSPoint(
            x: max(0, visibleRect.minX - containerOrigin.x),
            y: max(0, visibleRect.minY - containerOrigin.y)
        )
        let glyphIndex = min(
            layoutManager.glyphIndex(for: point, in: textContainer),
            layoutManager.numberOfGlyphs - 1
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )

        return MarkdownEditorViewportSnapshot(
            documentID: documentID,
            selection: selectedRange(),
            topVisibleCharacterIndex: characterIndex,
            verticalOffset: visibleRect.minY - glyphRect.minY - containerOrigin.y
        )
    }

    func restoreViewport(_ snapshot: MarkdownEditorViewportSnapshot) {
        let textLength = string.utf16.count
        setSelectedRange(snapshot.clampedSelection(textLength: textLength))

        guard let characterIndex = snapshot.topVisibleCharacterIndex,
              textLength > 0,
              let layoutManager,
              let textContainer,
              let scrollView = enclosingScrollView else { return }

        layoutManager.ensureLayout(for: textContainer)
        let safeCharacterIndex = min(characterIndex, textLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeCharacterIndex)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        let targetY = glyphRect.minY + textContainerOrigin.y + snapshot.verticalOffset
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: max(0, targetY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind?()
            return true
        }
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            if pasteImage(from: .general) { return true }
            if pastePlainText(from: .general) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    func revealFindMatch(_ range: NSRange) -> Bool {
        let textLength = (string as NSString).length
        guard range.location != NSNotFound,
              range.location <= textLength,
              NSMaxRange(range) <= textLength else { return false }

        setSelectedRange(range)
        scrollRangeToVisible(range)
        showFindIndicator(for: range)
        return true
    }

    override func paste(_ sender: Any?) {
        if pasteImage(from: .general) { return }
        if pastePlainText(from: .general) { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        image(from: sender.draggingPasteboard) == nil ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if pasteImage(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    @discardableResult
    func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        guard let image = image(from: pasteboard) else { return false }
        guard let markdown = onPasteImage?(image) else { return true }

        return insertImage(image, markdown: markdown)
    }

    @discardableResult
    func insertImage(_ image: NSImage, markdown: String) -> Bool {

        let content = string as NSString
        let selection = selectedRange()
        let location = min(selection.location, content.length)
        let length = min(selection.length, content.length - location)
        let safeRange = NSRange(location: location, length: length)
        let previousIsNewline = location == 0 || content.character(at: location - 1) == 10
        let nextLocation = NSMaxRange(safeRange)
        let nextIsNewline = nextLocation < content.length && content.character(at: nextLocation) == 10
        let attributedInsertion = NSMutableAttributedString()
        if !previousIsNewline {
            attributedInsertion.append(NSAttributedString(string: "\n", attributes: Self.defaultTextAttributes))
        }
        attributedInsertion.append(imageAttachment(image: image, markdown: markdown))
        if !nextIsNewline {
            attributedInsertion.append(NSAttributedString(string: "\n", attributes: Self.defaultTextAttributes))
        }
        guard shouldChangeText(in: safeRange, replacementString: nil) else { return true }
        textStorage?.replaceCharacters(in: safeRange, with: attributedInsertion)
        didChangeText()
        setSelectedRange(NSRange(location: location + attributedInsertion.length, length: 0))
        return true
    }

    @discardableResult
    func apply(_ command: MarkdownEditorCommand) -> Bool {
        switch command {
        case .heading(let level):
            return setHeadingLevel(level)
        case .bullet:
            return toggleSelectedLinePrefix("- ", recognizedPrefixes: ["- ", "* ", "+ "])
        case .quote:
            return toggleSelectedLinePrefix("> ", recognizedPrefixes: ["> "])
        case .code:
            return wrapSelectionAsCode()
        case .table(let columns, let dataRows):
            return insertTable(columns: columns, dataRows: dataRows)
        case .formatJSON:
            return formatSelectedJSON()
        }
    }

    func setMarkdown(_ markdown: String, resolveImage: (String) -> NSImage?) {
        let normalizedMarkdown = MarkdownImageSyntax.normalized(markdown)
        let output = NSMutableAttributedString(string: normalizedMarkdown, attributes: Self.defaultTextAttributes)
        let fullRange = NSRange(location: 0, length: normalizedMarkdown.utf16.count)
        let matches = Self.imageMarkdownRegex.matches(in: normalizedMarkdown, range: fullRange)
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let pathRange = Range(match.range(at: 1), in: normalizedMarkdown) else { continue }
            let path = String(normalizedMarkdown[pathRange])
            guard let image = resolveImage(path) else { continue }
            let marker = (normalizedMarkdown as NSString).substring(with: match.range)
            output.replaceCharacters(
                in: match.range,
                with: imageAttachment(image: image, markdown: marker)
            )
        }
        applyCodeTypography(to: output)
        textStorage?.setAttributedString(output)
        typingAttributes = Self.defaultTextAttributes
    }

    private func pastePlainText(from pasteboard: NSPasteboard) -> Bool {
        guard let value = pasteboard.string(forType: .string) else { return false }
        insertText(value, replacementRange: selectedRange())
        return true
    }

    private func setHeadingLevel(_ level: Int?) -> Bool {
        if let level, !(1...6).contains(level) { return false }
        let targetRange = selectedLineRange()
        let source = (string as NSString).substring(with: targetRange)
        let lines = source.components(separatedBy: "\n")
        let transformed = lines.enumerated().map { index, line in
            guard !(line.isEmpty && index == lines.count - 1) else { return "" }
            let plainLine = removingHeadingPrefix(from: line)
            guard let level else { return plainLine }
            return String(repeating: "#", count: level) + " " + plainLine
        }.joined(separator: "\n")
        return replaceText(in: targetRange, with: transformed, selectReplacement: true)
    }

    private func removingHeadingPrefix(from line: String) -> String {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return line }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first == " " || remainder.first == "\t" else { return line }
        return String(remainder.dropFirst())
    }

    private func toggleSelectedLinePrefix(_ preferredPrefix: String, recognizedPrefixes: [String]) -> Bool {
        let targetRange = selectedLineRange()
        let source = (string as NSString).substring(with: targetRange)
        let lines = source.components(separatedBy: "\n")
        let contentLines = lines.enumerated().filter { index, line in
            !(line.isEmpty && index == lines.count - 1) && !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !contentLines.isEmpty else { return false }

        let shouldRemove = contentLines.allSatisfy { _, line in
            recognizedPrefix(in: line, prefixes: recognizedPrefixes) != nil
        }
        let transformed = lines.enumerated().map { index, line in
            guard !(line.isEmpty && index == lines.count - 1),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let indentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let content = String(line.dropFirst(indentation.count))

            if let existing = recognizedPrefixes.first(where: { content.hasPrefix($0) }) {
                let unprefixed = String(content.dropFirst(existing.count))
                return shouldRemove ? indentation + unprefixed : indentation + preferredPrefix + unprefixed
            }
            return shouldRemove ? line : indentation + preferredPrefix + content
        }.joined(separator: "\n")
        return replaceText(in: targetRange, with: transformed, selectReplacement: true)
    }

    private func recognizedPrefix(in line: String, prefixes: [String]) -> String? {
        let indentationCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let content = line.dropFirst(indentationCount)
        return prefixes.first(where: { content.hasPrefix($0) })
    }

    private func wrapSelectionAsCode() -> Bool {
        let selection = safeSelectedRange()
        let targetRange: NSRange
        if selection.length > 0 {
            targetRange = selection
        } else {
            let fullRange = NSRange(location: 0, length: (string as NSString).length)
            targetRange = Self.fencedCodeRegex.matches(in: string, range: fullRange)
                .map(\.range)
                .first(where: { selection.location >= $0.location && selection.location <= NSMaxRange($0) })
                ?? selectedLineRange()
        }
        let source = (string as NSString).substring(with: targetRange)
        if let unfenced = removingCodeFence(from: source) {
            return replaceText(in: targetRange, with: unfenced, selectReplacement: true)
        }
        let suffix = source.hasSuffix("\n") ? "```" : "\n```"
        return replaceText(
            in: targetRange,
            with: "```text\n" + source + suffix,
            selectReplacement: true
        )
    }

    private func removingCodeFence(from source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard lines.count >= 2,
              lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true,
              lines.last?.trimmingCharacters(in: .whitespaces) == "```" else { return nil }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private func formatSelectedJSON() -> Bool {
        let selection = safeSelectedRange()
        let targetRange = jsonFormattingRange(for: selection)
        let source = (string as NSString).substring(with: targetRange)
        guard let formatted = MarkdownJSONFormatter.format(source) else { return false }
        guard replaceText(in: targetRange, with: formatted, selectReplacement: true) else { return false }
        if let textStorage { applyCodeTypography(to: textStorage) }
        return true
    }

    private func jsonFormattingRange(for selection: NSRange) -> NSRange {
        if selection.length > 0 { return selection }

        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        if let fencedRange = Self.fencedJSONRegex.matches(in: string, range: fullRange)
            .map(\.range)
            .first(where: { selection.location >= $0.location && selection.location <= NSMaxRange($0) }) {
            return fencedRange
        }
        return fullRange
    }

    @discardableResult
    func insertTable(columns: Int, dataRows: Int) -> Bool {
        let table = MarkdownTableTemplate.make(columns: columns, dataRows: dataRows)
        let selection = safeSelectedRange()
        let source = string as NSString
        let before = source.substring(to: selection.location)
        let after = source.substring(from: NSMaxRange(selection))
        let prefix: String
        if before.isEmpty || before.hasSuffix("\n\n") {
            prefix = ""
        } else if before.hasSuffix("\n") {
            prefix = "\n"
        } else {
            prefix = "\n\n"
        }
        let suffix: String
        if after.isEmpty {
            suffix = "\n"
        } else if after.hasPrefix("\n\n") {
            suffix = ""
        } else if after.hasPrefix("\n") {
            suffix = "\n"
        } else {
            suffix = "\n\n"
        }
        let replacement = prefix + table + suffix
        guard replaceText(in: selection, with: replacement, selectReplacement: false) else { return false }

        let cellRange = (replacement as NSString).range(of: "列 1")
        if cellRange.location != NSNotFound {
            setSelectedRange(NSRange(location: selection.location + cellRange.location, length: cellRange.length))
            window?.makeFirstResponder(self)
        }
        return true
    }

    private func applyCodeTypography(to storage: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: storage.length)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let codeParagraphStyle = NSMutableParagraphStyle()
        codeParagraphStyle.lineSpacing = 2
        codeParagraphStyle.paragraphSpacing = 0
        let codeAttributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .kern: NSNumber(0),
            .paragraphStyle: codeParagraphStyle
        ]

        if JSONPrettyPrinter.format(storage.string) != nil {
            storage.addAttributes(codeAttributes, range: fullRange)
            return
        }

        for match in Self.fencedCodeRegex.matches(in: storage.string, range: fullRange) {
            storage.addAttributes(codeAttributes, range: match.range)
        }
    }

    private func safeSelectedRange() -> NSRange {
        let length = (string as NSString).length
        let selection = selectedRange()
        let location = min(selection.location, length)
        return NSRange(location: location, length: min(selection.length, length - location))
    }

    private func selectedLineRange() -> NSRange {
        (string as NSString).lineRange(for: safeSelectedRange())
    }

    private func replaceText(in range: NSRange, with replacement: String, selectReplacement: Bool) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        let attributed = NSAttributedString(string: replacement, attributes: Self.defaultTextAttributes)
        textStorage?.replaceCharacters(in: range, with: attributed)
        didChangeText()
        let cursorRange = selectReplacement
            ? NSRange(location: range.location, length: attributed.length)
            : NSRange(location: range.location + attributed.length, length: 0)
        setSelectedRange(cursorRange)
        window?.makeFirstResponder(self)
        return true
    }

    private func imageAttachment(image: NSImage, markdown: String) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        let imageSize = image.size
        let widthScale = imageSize.width > 0 ? 520 / imageSize.width : 1
        let heightScale = imageSize.height > 0 ? 320 / imageSize.height : 1
        let scale = min(1, widthScale, heightScale)
        attachment.bounds = NSRect(
            x: 0,
            y: -4,
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
        let output = NSMutableAttributedString(attachment: attachment)
        output.addAttribute(
            .quietPaperImageMarkdown,
            value: markdown,
            range: NSRange(location: 0, length: output.length)
        )
        return output
    }

    private func image(from pasteboard: NSPasteboard) -> NSImage? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: NSImage.imageTypes
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           let imageURL = urls.first,
           let image = NSImage(contentsOf: imageURL) {
            return image
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            return image
        }

        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                guard let contentType = UTType(type.rawValue),
                      contentType.conforms(to: .image),
                      let data = item.data(forType: type),
                      let image = NSImage(data: data) else { continue }
                return image
            }
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("org.webmproject.webp")
        ]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        return NSImage(pasteboard: pasteboard)
    }

    private static let imageMarkdownRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]\n]*\]\(([^)\n]+)\)"#
    )
}

private extension NSAttributedString.Key {
    static let quietPaperImageMarkdown = NSAttributedString.Key("QuietPaperImageMarkdown")
}
