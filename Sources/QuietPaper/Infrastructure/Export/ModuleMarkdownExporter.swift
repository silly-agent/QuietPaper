import Foundation

struct ModuleExportSection {
    let name: String
    let notes: [Note]
}

enum ModuleMarkdownExporter {
    static func mergedMarkdown(moduleName: String, notes: [Note]) -> String {
        var sections = ["# \(headingText(moduleName))"]

        for note in notes {
            let body = exportedBody(for: note).trimmingCharacters(in: .newlines)
            let section = body.isEmpty
                ? "## \(headingText(note.title))"
                : "## \(headingText(note.title))\n\n\(body)"
            sections.append(section)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    static func writeMerged(moduleName: String, notes: [Note], to destination: URL) throws {
        try mergedMarkdown(moduleName: moduleName, notes: notes)
            .write(to: destination, atomically: true, encoding: .utf8)
    }

    static func writeArchive(moduleName: String, notes: [Note], to destination: URL) throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("QuietPaper-Module-Export-\(UUID().uuidString)", isDirectory: true)
        let exportFolder = temporaryRoot
            .appendingPathComponent(safeBaseName(moduleName, fallback: "模块导出"), isDirectory: true)

        try fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try writeSeparateFiles(notes: notes, to: exportFolder)
        try writeZipArchive(from: exportFolder, to: destination)
    }

    static func mergedProjectMarkdown(
        projectName: String,
        rootNotes: [Note],
        modules: [ModuleExportSection]
    ) -> String {
        var sections = ["# \(headingText(projectName))"]

        for note in rootNotes {
            sections.append(markdownSection(for: note, headingLevel: 2))
        }
        for module in modules {
            sections.append("## \(headingText(module.name))")
            for note in module.notes {
                sections.append(markdownSection(for: note, headingLevel: 3))
            }
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    static func writeMergedProject(
        projectName: String,
        rootNotes: [Note],
        modules: [ModuleExportSection],
        to destination: URL
    ) throws {
        try mergedProjectMarkdown(projectName: projectName, rootNotes: rootNotes, modules: modules)
            .write(to: destination, atomically: true, encoding: .utf8)
    }

    static func writeProjectArchive(
        projectName: String,
        rootNotes: [Note],
        modules: [ModuleExportSection],
        to destination: URL
    ) throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("QuietPaper-Project-Export-\(UUID().uuidString)", isDirectory: true)
        let exportFolder = temporaryRoot
            .appendingPathComponent(safeBaseName(projectName, fallback: "项目导出"), isDirectory: true)

        try fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try writeProjectFiles(rootNotes: rootNotes, modules: modules, to: exportFolder)
        try writeZipArchive(from: exportFolder, to: destination)
    }

    static func writeProjectFiles(
        rootNotes: [Note],
        modules: [ModuleExportSection],
        to directory: URL
    ) throws {
        let fileManager = FileManager.default
        try writeSeparateFiles(notes: rootNotes, to: directory)
        var usedDirectoryNames = Set<String>()

        for module in modules {
            let directoryName = uniqueBaseName(
                for: module.name,
                fallback: "未命名模块",
                usedNames: &usedDirectoryNames
            )
            let moduleDirectory = directory.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
            try writeSeparateFiles(notes: module.notes, to: moduleDirectory)
        }
    }

    private static func writeZipArchive(from sourceDirectory: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let stagedArchive = destination.deletingLastPathComponent()
            .appendingPathComponent(".QuietPaper-Export-\(UUID().uuidString).zip")
        defer { try? fileManager.removeItem(at: stagedArchive) }

        try createZipArchive(from: sourceDirectory, at: stagedArchive)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagedArchive)
        } else {
            try fileManager.moveItem(at: stagedArchive, to: destination)
        }
    }

    static func writeSeparateFiles(notes: [Note], to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var usedNames = Set<String>()

        for note in notes {
            let fileName = uniqueMarkdownFileName(for: note.title, usedNames: &usedNames)
            let destination = directory.appendingPathComponent(fileName, isDirectory: false)
            try exportedBody(for: note).write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    static func safeBaseName(_ value: String, fallback: String = "未命名") -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        var cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        while cleaned.contains("--") {
            cleaned = cleaned.replacingOccurrences(of: "--", with: "-")
        }
        if cleaned.lowercased().hasSuffix(".md") {
            cleaned.removeLast(3)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        }
        if cleaned.isEmpty { cleaned = fallback }
        return String(cleaned.prefix(120))
    }

    private static func exportedBody(for note: Note) -> String {
        switch note.kind {
        case .markdown:
            return note.contentMarkdown
        case .request:
            return fencedJSON(note.contentMarkdown, label: "HTTP 请求")
        case .websocket:
            return fencedJSON(note.contentMarkdown, label: "WebSocket 请求")
        case .connection:
            return fencedJSON(note.contentMarkdown, label: "数据库连接")
        }
    }

    private static func markdownSection(for note: Note, headingLevel: Int) -> String {
        let heading = String(repeating: "#", count: headingLevel)
        let body = exportedBody(for: note).trimmingCharacters(in: .newlines)
        return body.isEmpty
            ? "\(heading) \(headingText(note.title))"
            : "\(heading) \(headingText(note.title))\n\n\(body)"
    }

    private static func fencedJSON(_ content: String, label: String) -> String {
        let body = content.trimmingCharacters(in: .newlines)
        return "> 文件类型：\(label)\n\n```json\n\(body)\n```\n"
    }

    private static func headingText(_ value: String) -> String {
        let singleLine = value
            .split(whereSeparator: \Character.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return singleLine.isEmpty ? "未命名" : singleLine
    }

    private static func uniqueMarkdownFileName(for title: String, usedNames: inout Set<String>) -> String {
        "\(uniqueBaseName(for: title, fallback: "未命名", usedNames: &usedNames)).md"
    }

    private static func uniqueBaseName(
        for value: String,
        fallback: String,
        usedNames: inout Set<String>
    ) -> String {
        let base = safeBaseName(value, fallback: fallback)
        var candidate = base
        var sequence = 2

        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(base) (\(sequence))"
            sequence += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    private static func createZipArchive(from sourceDirectory: URL, at destination: URL) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", sourceDirectory.path, destination.path]
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw QuietPaperError.export(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw QuietPaperError.export(detail?.isEmpty == false ? detail! : "无法创建 ZIP 压缩包")
        }
    }
}
