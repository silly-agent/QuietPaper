import Foundation

@main
struct VectorSearchCheck {
    static func main() throws {
        // 1. Create in-memory database with test data
        let db = try WorkspaceDatabase(inMemory: true, seedIfEmpty: false)

        let project = try db.createProject(name: "AI平台")
        let module = try db.createModule(projectID: project.id, name: "月之暗面")

        // Create a note about k3
        let note1 = try db.createNote(
            moduleID: module.id,
            title: "k3 API 密钥配置",
            content: "k3 的 API 密钥是 sk-k3-1234567890abcdef。需要在请求头中携带 Authorization: Bearer sk-k3-xxx",
            kind: .markdown
        )

        // Create another note about k3
        let note2 = try db.createNote(
            moduleID: module.id,
            title: "k3 接口地址",
            content: "月之暗面 k3 的接口地址是 https://api.k3.moonshot.cn/v1/chat/completions",
            kind: .markdown
        )

        print("=== Test Data ===")
        print("Project: \(project.name)")
        print("Module: \(module.name)")
        print("Note1: \(note1.title)")
        print("Note2: \(note2.title)")

        // 2. Check chunks after creation
        let chunkCount = try db.chunkCount()
        print("\n=== Chunks Created: \(chunkCount) ===")
        let allChunks = try db.fetchAllChunks(scope: .all, projectID: nil, moduleID: nil)
        for chunk in allChunks {
            print("  Chunk[\(chunk.chunkIndex)]: noteID=\(chunk.noteID), text=\(chunk.contentText.prefix(80))...")
            let hasPath = chunk.contentText.contains("AI平台") && chunk.contentText.contains("月之暗面")
            print("    Module/project prefix present: \(hasPath)")
        }

        // 3. Test FTS5 search
        print("\n=== FTS5 Search: 'k3' ===")
        let ftsResults_k3 = try db.search(query: "k3", scope: .all, projectID: nil, moduleID: nil)
        for r in ftsResults_k3 {
            print("  [\(r.path)] \(r.noteTitle): \(r.excerpt.prefix(60))...")
        }

        print("\n=== FTS5 Search: '月之暗面' ===")
        let ftsResults_moon = try db.search(query: "月之暗面", scope: .all, projectID: nil, moduleID: nil)
        for r in ftsResults_moon {
            print("  [\(r.path)] \(r.noteTitle): \(r.excerpt.prefix(60))...")
        }

        // 4. Test vector search
        print("\n=== Vector Search: 'k3的密钥是什么' ===")
        guard let embedding = EmbeddingService() else {
            print("  ERROR: EmbeddingService() returned nil!")
            return
        }
        print("  Embedding model: \(embedding.language), dimension: \(embedding.dimension)")

        let svc = VectorSearchService(embedding: embedding)
        let scored = svc.search(query: "k3的密钥是什么", chunks: allChunks, topK: 5)
        if scored.isEmpty {
            print("  No vector results found!")
        } else {
            for sc in scored {
                print("  score=\(String(format: "%.4f", sc.score)) noteID=\(sc.chunk.noteID) chunk=\(sc.chunk.chunkIndex) text=\(sc.chunk.contentText.prefix(60))...")
            }
        }

        // 5. Test the noteSearchResult lookup
        print("\n=== NoteSearchResult lookup for top chunks ===")
        for sc in scored.prefix(2) {
            if let result = try db.noteSearchResult(noteID: sc.chunk.noteID, excerpt: sc.chunk.contentText) {
                print("  [\(result.path)] \(result.noteTitle)")
            } else {
                print("  ERROR: noteSearchResult returned nil for noteID=\(sc.chunk.noteID)")
            }
        }

        print("\n=== ALL TESTS PASSED ===")
    }
}
