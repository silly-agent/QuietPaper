import AppKit
import Foundation

final class AttachmentStore: @unchecked Sendable {
    let rootURL: URL

    init(databaseURL: URL?) {
        if let databaseURL {
            rootURL = databaseURL.deletingLastPathComponent()
        } else {
            rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("QuietPaperPreview", isDirectory: true)
        }
    }

    func importImage(_ image: NSImage, noteID: UUID) throws -> (relativePath: String, size: Int) {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:]) else {
            throw QuietPaperError.attachment("无法转换图片")
        }
        let relative = "attachments/\(noteID.uuidString)/\(UUID().uuidString).png"
        let destination = rootURL.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return (relative, data.count)
    }

    func url(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    func removeAttachments(noteID: UUID) throws {
        let directory = rootURL.appendingPathComponent("attachments/\(noteID.uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
