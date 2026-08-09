#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_PATH="${TMPDIR:-/tmp}/quiet-paper-checks"

cd "$PROJECT_DIR"
swiftc \
  -swift-version 6 \
  -I "$PROJECT_DIR/Sources/CSQLite" \
  -Xcc "-fmodule-map-file=$PROJECT_DIR/Sources/CSQLite/module.modulemap" \
  "$PROJECT_DIR/Sources/QuietPaper/Domain/Models.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Domain/Protocols.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Features/Shared/WritingFocusBlur.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Features/NoteList/NoteRangeSelection.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Features/NoteEditor/EditorFind.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownPlainText.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownImageSyntax.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownInlineText.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownJSONFormatter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownParser.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Export/ModuleMarkdownExporter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/CURLRequestImporter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestClient.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/WebSocket/WebSocketModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/WebSocket/WebSocketClient.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Database/DatabaseConnectionModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Database/DatabaseCommandPolicy.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/EmbeddingService.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/RetrievalQueryTerms.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/VectorSearchService.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Data/WorkspaceDatabase.swift" \
  "$PROJECT_DIR/Tests/QuietPaperChecks.swift" \
  -lsqlite3 \
  -framework SwiftUI \
  -framework NaturalLanguage \
  -o "$OUTPUT_PATH"
"$OUTPUT_PATH"

EDITOR_OUTPUT_PATH="${TMPDIR:-/tmp}/quiet-paper-editor-check"
swiftc \
  -swift-version 6 \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownInlineText.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownParser.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownImageSyntax.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownJSONFormatter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Features/NoteEditor/EditorFind.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Features/NoteEditor/MarkdownEditor.swift" \
  "$PROJECT_DIR/Tests/EditorInputCheck.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$EDITOR_OUTPUT_PATH"
"$EDITOR_OUTPUT_PATH"

AUTOSAVE_OUTPUT_PATH="${TMPDIR:-/tmp}/quiet-paper-autosave-check"
swiftc \
  -swift-version 6 \
  -I "$PROJECT_DIR/Sources/CSQLite" \
  -Xcc "-fmodule-map-file=$PROJECT_DIR/Sources/CSQLite/module.modulemap" \
  "$PROJECT_DIR/Sources/QuietPaper/Domain/Models.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Domain/Protocols.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownPlainText.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownImageSyntax.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownJSONFormatter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Markdown/MarkdownParser.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Export/ModuleMarkdownExporter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/CURLRequestImporter.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestClient.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/WebSocket/WebSocketModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Database/DatabaseConnectionModels.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Database/DatabaseCommandPolicy.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Keychain/KeychainStore.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/AI/LocalGroundedAIProvider.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/AI/DeepSeekAIProvider.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/EmbeddingService.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/RetrievalQueryTerms.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Vector/VectorSearchService.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Attachments/AttachmentStore.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Infrastructure/Theme.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/Data/WorkspaceDatabase.swift" \
  "$PROJECT_DIR/Sources/QuietPaper/App/AppModel.swift" \
  "$PROJECT_DIR/Tests/AutosaveInputCheck.swift" \
  -lsqlite3 \
  -framework AppKit \
  -framework Combine \
  -framework Security \
  -framework NaturalLanguage \
  -o "$AUTOSAVE_OUTPUT_PATH"
DEEPSEEK_API_KEY="quiet-paper-test-key" "$AUTOSAVE_OUTPUT_PATH"
