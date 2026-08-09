import SwiftUI

enum WritingFocusBlurPreference {
    static let defaultsKey = "QuietPaper.writingFocusBlurEnabled"
    static let defaultValue = true
}

enum WritingEditorFocusTarget: Hashable {
    case title
    case body
}

enum WritingNavigationRegion: Hashable {
    case projectSidebar
    case noteList
}

struct WritingFocusBlurState {
    private var focusedEditorTargets: Set<WritingEditorFocusTarget> = []
    private var hoveredNavigationRegions: Set<WritingNavigationRegion> = []
    private var isEditorHeaderHovered = false

    var shouldBlurNavigation: Bool {
        !focusedEditorTargets.isEmpty && hoveredNavigationRegions.isEmpty
    }

    func shouldBlurNavigation(isEnabled: Bool) -> Bool {
        isEnabled && shouldBlurNavigation
    }

    func shouldBlurEditorHeader(isEnabled: Bool) -> Bool {
        isEnabled
            && focusedEditorTargets.contains(.body)
            && !focusedEditorTargets.contains(.title)
            && !isEditorHeaderHovered
    }

    mutating func setEditorFocus(_ focused: Bool, target: WritingEditorFocusTarget) {
        if focused {
            focusedEditorTargets.insert(target)
        } else {
            focusedEditorTargets.remove(target)
        }
    }

    mutating func setNavigationHover(_ hovering: Bool, region: WritingNavigationRegion) {
        if hovering {
            hoveredNavigationRegions.insert(region)
        } else {
            hoveredNavigationRegions.remove(region)
        }
    }

    mutating func setEditorHeaderHover(_ hovering: Bool) {
        isEditorHeaderHovered = hovering
    }
}

private struct WritingFocusBlurModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 5.5 : 0)
            .saturation(isActive ? 0.62 : 1)
            .opacity(isActive ? 0.76 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isActive)
    }
}

extension View {
    func writingFocusBlur(isActive: Bool) -> some View {
        modifier(WritingFocusBlurModifier(isActive: isActive))
    }
}
