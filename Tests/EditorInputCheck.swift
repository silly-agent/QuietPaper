import AppKit
import SwiftUI

@main
@MainActor
struct EditorInputCheck {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)

        var content = ""
        let imageMarkdown = "![图片](attachments/test.png)"
        var receivedImages = 0
        var findRequests = 0
        let editorController = MarkdownEditorController()
        let editor = MarkdownEditor(
            text: Binding(
                get: { content },
                set: { content = $0 }
            ),
            onPasteImage: { _ in
                receivedImages += 1
                return imageMarkdown
            },
            resolveImage: { _ in nil },
            controller: editorController,
            onFind: { findRequests += 1 }
        )
        let host = NSHostingView(rootView: editor.frame(width: 640, height: 420))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let textView: PastingTextView = findSubview(in: host) else {
            fatalError("未找到 MarkdownEditor 的文本视图")
        }
        precondition(textView.isEditable, "内容区必须可编辑")
        precondition(textView.isSelectable, "内容区必须可选择")
        precondition(textView.frame.width > 0 && textView.frame.height > 0, "内容区尺寸必须有效")
        precondition(window.makeFirstResponder(textView), "内容区必须能获得输入焦点")

        let findEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        )!
        precondition(textView.performKeyEquivalent(with: findEvent), "Command-F 必须由编辑器处理")
        precondition(findRequests == 1, "Command-F 必须请求打开查找栏")
        verifyPasteShortcutFollowsFirstResponder()

        textView.setMarkdown("关键字 one 关键字", resolveImage: { _ in nil })
        let findRanges = editorController.findRanges(for: "关键字")
        precondition(findRanges.count == 2, "编辑模式必须找到所有正文匹配")
        precondition(editorController.revealFindMatch(findRanges[1]), "编辑模式必须能够定位下一处匹配")
        precondition(textView.selectedRange() == findRanges[1], "定位后必须选中当前匹配")
        precondition(editorController.revealFindMatch(findRanges[0]), "循环后必须能够回到第一处匹配")
        precondition(textView.selectedRange() == findRanges[0], "循环后必须选中第一处匹配")
        textView.setMarkdown("", resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.insertText("可以输入中文", replacementRange: textView.selectedRange())
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(textView.string == "可以输入中文", "内容区必须接受键盘文本")
        precondition(content == "可以输入中文", "输入必须同步到 SwiftUI Binding")

        guard let imageData = makePNG() else {
            fatalError("无法生成图片粘贴测试数据")
        }
        let imagePasteboard = NSPasteboard(name: .init("QuietPaperEditorImageCheck"))
        imagePasteboard.clearContents()
        imagePasteboard.setData(imageData, forType: .png)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        precondition(textView.pasteImage(from: imagePasteboard), "内容区必须接受剪贴板图片数据")
        precondition(receivedImages == 1, "图片必须传递给附件存储回调")
        precondition(textView.string.contains("\u{FFFC}"), "图片必须在编辑区内联显示")
        precondition(textView.markdownString.contains(imageMarkdown), "图片引用必须保留在 Markdown 源文档")
        precondition(content == textView.markdownString, "图片引用必须同步到 SwiftUI Binding")

        let temporaryImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiet-paper-editor-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryImageURL) }
        try! imageData.write(to: temporaryImageURL, options: .atomic)
        let filePasteboard = NSPasteboard(name: .init("QuietPaperEditorFileCheck"))
        filePasteboard.clearContents()
        filePasteboard.writeObjects([temporaryImageURL as NSURL])
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        precondition(textView.pasteImage(from: filePasteboard), "内容区必须接受复制的图片文件")
        precondition(receivedImages == 2, "图片文件必须传递给附件存储回调")

        let multiImageEditor = PastingTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        multiImageEditor.isRichText = true
        multiImageEditor.typingAttributes = PastingTextView.defaultTextAttributes
        var pastedImageIndex = 0
        multiImageEditor.onPasteImage = { _ in
            pastedImageIndex += 1
            return "![图片](attachments/image-\(pastedImageIndex).png)"
        }
        precondition(multiImageEditor.pasteImage(from: imagePasteboard), "第一张图片必须粘贴成功")
        precondition(multiImageEditor.pasteImage(from: imagePasteboard), "第二张图片必须粘贴成功")
        let expectedMultipleImages = "![图片](attachments/image-1.png)\n![图片](attachments/image-2.png)\n"
        precondition(
            multiImageEditor.markdownString == expectedMultipleImages,
            "连续粘贴的图片必须各占一行，实际为：\(multiImageEditor.markdownString.debugDescription)"
        )

        let reactiveState = ReactiveEditorState()
        var reactiveImageIndex = 0
        let reactiveEditor = ReactiveEditorHarness(
            state: reactiveState,
            onPasteImage: { _ in
                reactiveImageIndex += 1
                return "![图片](attachments/reactive-\(reactiveImageIndex).png)"
            }
        )
        let reactiveHost = NSHostingView(rootView: reactiveEditor.frame(width: 640, height: 420))
        reactiveHost.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let reactiveWindow = NSWindow(
            contentRect: reactiveHost.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        reactiveWindow.contentView = reactiveHost
        reactiveWindow.makeKey()
        reactiveHost.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        guard let reactiveTextView: PastingTextView = findSubview(in: reactiveHost) else {
            fatalError("未找到响应式 MarkdownEditor 文本视图")
        }
        precondition(reactiveTextView.pasteImage(from: imagePasteboard), "响应式编辑器第一张图片必须粘贴成功")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(reactiveTextView.pasteImage(from: imagePasteboard), "响应式编辑器第二张图片必须粘贴成功")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let expectedReactiveImages = "![图片](attachments/reactive-1.png)\n![图片](attachments/reactive-2.png)\n"
        precondition(
            reactiveState.text == expectedReactiveImages,
            "SwiftUI 回写后图片不能重复或粘连，实际为：\(reactiveState.text.debugDescription)"
        )

        let restoredMarkdown = "前文\n\(imageMarkdown)\n后文"
        textView.setMarkdown(restoredMarkdown, resolveImage: { _ in NSImage(data: imageData) })
        precondition(textView.string.contains("\u{FFFC}"), "重新打开笔记时必须恢复内联图片")
        precondition(textView.markdownString == restoredMarkdown, "内联图片不能破坏 Markdown 原文")

        let firstMarker = "![图片](attachments/first.png)"
        let secondMarker = "![图片](attachments/second.png)"
        textView.setMarkdown(firstMarker + "\n" + secondMarker + "\n", resolveImage: { _ in NSImage(data: imageData) })
        textView.insertText("图片之间的文字\n", replacementRange: NSRange(location: 2, length: 0))
        let textBetweenImages = firstMarker + "\n图片之间的文字\n" + secondMarker + "\n"
        precondition(textView.markdownString == textBetweenImages, "图片之间输入的文字不能在序列化时消失")
        textView.setMarkdown(textView.markdownString, resolveImage: { _ in NSImage(data: imageData) })
        precondition(textView.markdownString == textBetweenImages, "编辑/预览切换后必须保留图片之间的文字")

        textView.setMarkdown("第一行\n第二行", resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        precondition(textView.apply(.quote), "引用工具栏命令必须执行")
        precondition(textView.markdownString == "第一行\n> 第二行", "引用命令只能作用于选中的第二行")

        textView.setMarkdown("第一行\n第二行", resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        precondition(textView.apply(.heading(level: 1)), "一级标题命令必须执行")
        precondition(textView.markdownString == "# 第一行\n# 第二行", "一级标题必须作用于所有选中行")
        precondition(textView.apply(.heading(level: 3)), "三级标题命令必须替换现有标题")
        precondition(textView.markdownString == "### 第一行\n### 第二行", "标题级别切换不能叠加井号")
        precondition(textView.apply(.heading(level: nil)), "正文命令必须移除标题")
        precondition(textView.markdownString == "第一行\n第二行", "正文命令必须恢复普通文本")

        precondition(textView.apply(.bullet), "列表命令必须添加列表标记")
        precondition(textView.markdownString == "- 第一行\n- 第二行", "列表命令必须作用于所有选中行")
        precondition(textView.apply(.bullet), "再次点击列表命令必须执行")
        precondition(textView.markdownString == "第一行\n第二行", "再次点击列表命令必须取消列表")

        precondition(textView.apply(.quote), "引用命令必须添加引用标记")
        precondition(textView.markdownString == "> 第一行\n> 第二行", "引用命令必须作用于所有选中行")
        precondition(textView.apply(.quote), "再次点击引用命令必须执行")
        precondition(textView.markdownString == "第一行\n第二行", "再次点击引用命令必须取消引用")

        textView.setMarkdown("let value = 1", resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        precondition(textView.apply(.code), "代码块命令必须包裹选区")
        precondition(textView.markdownString == "```text\nlet value = 1\n```", "代码块必须使用 Markdown 围栏")
        precondition(textView.apply(.code), "再次点击代码块命令必须执行")
        precondition(textView.markdownString == "let value = 1", "再次点击代码块命令必须移除围栏")

        textView.setMarkdown("表格前", resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        precondition(textView.apply(.table(columns: 3, dataRows: 2)), "表格命令必须执行")
        precondition(
            textView.markdownString == "表格前\n\n| 列 1 | 列 2 | 列 3 |\n| --- | --- | --- |\n| 内容 1-1 | 内容 1-2 | 内容 1-3 |\n| 内容 2-1 | 内容 2-2 | 内容 2-3 |\n",
            "表格命令必须插入标准 Markdown 表格，实际为：\(textView.markdownString.debugDescription)"
        )
        let selectedTableCell = (textView.string as NSString).substring(with: textView.selectedRange())
        precondition(selectedTableCell == "列 1", "插入表格后必须默认选中第一个表头单元格")

        textView.setMarkdown(#"{"b":1,"a":2}"#, resolveImage: { _ in nil })
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        precondition(textView.apply(.formatJSON), "选中的 JSON 必须能够格式化")
        precondition(textView.markdownString.contains("\n  \"a\": 2"), "JSON 格式化必须产生缩进并排序")

        let mixedMarkdown = "说明文字\n\n```json\n{\"nested\":{\"value\":1}}\n```\n\n结尾"
        textView.setMarkdown(mixedMarkdown, resolveImage: { _ in nil })
        let jsonCursor = (textView.string as NSString).range(of: #"{"nested"#).location
        textView.setSelectedRange(NSRange(location: jsonCursor, length: 0))
        precondition(textView.apply(.formatJSON), "光标所在的 JSON 代码块必须能够单独格式化")
        precondition(
            textView.markdownString == "说明文字\n\n```json\n{\n  \"nested\": {\n    \"value\": 1\n  }\n}\n```\n\n结尾",
            "格式化 JSON 代码块不能改动周围 Markdown"
        )
        let formattedJSONLocation = (textView.string as NSString).range(of: #""nested""#).location
        let formattedJSONFont = textView.textStorage?.attribute(
            .font,
            at: formattedJSONLocation,
            effectiveRange: nil
        ) as? NSFont
        precondition(
            formattedJSONFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
            "编辑器中的代码块必须使用等宽字体"
        )
        let formattedJSONParagraphStyle = textView.textStorage?.attribute(
            .paragraphStyle,
            at: formattedJSONLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle
        precondition(
            (formattedJSONParagraphStyle?.lineSpacing ?? .infinity) <= 2
                && (formattedJSONParagraphStyle?.paragraphSpacing ?? .infinity) == 0,
            "JSON 代码块必须使用紧凑行距"
        )

        let paragraphStyle = PastingTextView.defaultTextAttributes[.paragraphStyle] as? NSParagraphStyle
        precondition((paragraphStyle?.lineSpacing ?? 0) >= 5, "编辑器正文必须增加行高")

        verifyTextSynchronization()
        verifyViewportRestoration()

        print("Quiet Paper editor input checks passed: 50/50")
    }

    private static func verifyPasteShortcutFollowsFirstResponder() {
        let editor = PastingTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        editor.isRichText = true
        editor.typingAttributes = PastingTextView.defaultTextAttributes
        editor.setMarkdown("正文", resolveImage: { _ in nil })
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))

        let input = NSTextField(frame: NSRect(x: 0, y: 170, width: 360, height: 24))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        container.addSubview(editor)
        container.addSubview(input)

        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKey()

        let pasteboard = NSPasteboard(name: .init("QuietPaperEditorFocusPasteCheck"))
        pasteboard.clearContents()
        pasteboard.setString("粘贴内容", forType: .string)

        precondition(window.makeFirstResponder(input), "标题或搜索输入框必须能获得焦点")
        precondition(!editor.handlePasteShortcut(from: pasteboard), "输入框聚焦时正文不能拦截粘贴")
        precondition(editor.markdownString == "正文", "输入框粘贴不能写入正文")

        precondition(window.makeFirstResponder(editor), "正文必须能获得焦点")
        precondition(editor.handlePasteShortcut(from: pasteboard), "正文聚焦时必须正常处理粘贴")
        precondition(editor.markdownString == "正文粘贴内容", "正文聚焦时粘贴内容必须写入正文")
    }

    private static func verifyTextSynchronization() {
        let firstDocumentID = UUID()
        var synchronizer = EditorTextSynchronizer(documentID: firstDocumentID, externalText: "旧正文")
        var editorTextReadCount = 0

        precondition(
            !synchronizer.shouldApplyExternalText(
                "旧正文",
                documentID: firstDocumentID,
                currentEditorText: {
                    editorTextReadCount += 1
                    return "旧正文"
                },
                hasMarkedText: false
            ) && editorTextReadCount == 0,
            "仅侧栏布局变化时不能重新扫描整篇编辑器正文"
        )

        synchronizer.editorDidChange(to: "正在输入")
        precondition(
            !synchronizer.shouldApplyExternalText(
                "旧正文",
                documentID: firstDocumentID,
                currentEditorText: { "正在输入" },
                hasMarkedText: false
            ),
            "旧的 SwiftUI 状态不能覆盖刚输入的文字"
        )
        precondition(
            !synchronizer.shouldApplyExternalText(
                "正在输入",
                documentID: firstDocumentID,
                currentEditorText: { "正在输入" },
                hasMarkedText: false
            ),
            "编辑器回写确认不能重复修改正文"
        )
        precondition(
            !synchronizer.shouldApplyExternalText(
                "外部变化",
                documentID: firstDocumentID,
                currentEditorText: { "输入法组合中" },
                hasMarkedText: true
            ),
            "输入法组合期间不能覆盖正文"
        )
        precondition(
            synchronizer.shouldApplyExternalText(
                "工具栏插入",
                documentID: firstDocumentID,
                currentEditorText: { "正在输入" },
                hasMarkedText: false
            ),
            "稳定状态下必须接受工具栏产生的正文变化"
        )
    }

    private static func verifyViewportRestoration() {
        let documentID = UUID()
        let controller = MarkdownEditorController()
        var content = (1...180).map {
            "第 \($0) 行：用于验证专注模式切换后仍停留在原来的阅读和编辑位置。"
        }.joined(separator: "\n")

        let firstEditor = MarkdownEditor(
            text: Binding(get: { content }, set: { content = $0 }),
            onPasteImage: { _ in nil },
            resolveImage: { _ in nil },
            documentID: documentID,
            controller: controller
        )
        let firstHost = NSHostingView(rootView: firstEditor.frame(width: 640, height: 260))
        firstHost.frame = NSRect(x: 0, y: 0, width: 640, height: 260)
        let firstWindow = NSWindow(
            contentRect: firstHost.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        firstWindow.contentView = firstHost
        firstWindow.makeKey()
        firstHost.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let firstTextView: PastingTextView = findSubview(in: firstHost) else {
            fatalError("未找到用于视口保存检查的文本视图")
        }
        let targetRange = (firstTextView.string as NSString).range(of: "第 120 行")
        precondition(targetRange.location != NSNotFound, "视口保存检查必须找到目标行")
        let expectedSelection = NSRange(location: targetRange.location + targetRange.length, length: 0)
        firstTextView.setSelectedRange(expectedSelection)
        firstTextView.scrollRangeToVisible(targetRange)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let expectedTopCharacter = firstTextView.viewportSnapshot(documentID: documentID).topVisibleCharacterIndex
        controller.captureViewport()

        let secondEditor = MarkdownEditor(
            text: Binding(get: { content }, set: { content = $0 }),
            onPasteImage: { _ in nil },
            resolveImage: { _ in nil },
            documentID: documentID,
            controller: controller,
            showsScrollIndicators: false
        )
        let secondHost = NSHostingView(rootView: secondEditor.frame(width: 480, height: 260))
        secondHost.frame = NSRect(x: 0, y: 0, width: 480, height: 260)
        let secondWindow = NSWindow(
            contentRect: secondHost.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        secondWindow.contentView = secondHost
        secondWindow.makeKey()
        secondHost.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let secondTextView: PastingTextView = findSubview(in: secondHost) else {
            fatalError("未找到用于视口恢复检查的文本视图")
        }
        let restoredTopCharacter = secondTextView.viewportSnapshot(documentID: documentID).topVisibleCharacterIndex
        precondition(secondTextView.selectedRange() == expectedSelection, "布局切换后必须恢复正文光标位置")
        precondition(
            restoredTopCharacter == expectedTopCharacter,
            "布局切换并重新换行后必须恢复可视区域顶部的正文锚点"
        )
    }

    private static func makePNG() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func findSubview<T: NSView>(in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match: T = findSubview(in: subview) { return match }
        }
        return nil
    }
}

@MainActor
private final class ReactiveEditorState: ObservableObject {
    @Published var text = ""
}

private struct ReactiveEditorHarness: View {
    @ObservedObject var state: ReactiveEditorState
    let onPasteImage: (NSImage) -> String?

    var body: some View {
        MarkdownEditor(
            text: $state.text,
            onPasteImage: onPasteImage,
            resolveImage: { _ in nil },
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
    }
}
