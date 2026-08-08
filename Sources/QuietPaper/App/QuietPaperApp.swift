import AppKit
import SwiftUI

@main
struct QuietPaperApp: App {
    @NSApplicationDelegateAdaptor(QuietPaperAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Quiet Paper") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-preview") ? .dark : nil)
                .frame(minWidth: 1_100, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    model.forceSave()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.forceSave()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建笔记") { _ = model.createNote() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("新建模块") { _ = model.createModule() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建文件") { _ = model.createProjectFile() }
                Button("新建请求") {
                    if model.selectedModule?.isProjectRoot == false {
                        _ = model.createRequest()
                    } else {
                        _ = model.createProjectRequest()
                    }
                }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("新建连接") {
                    if model.selectedModule?.isProjectRoot == false {
                        _ = model.createConnection()
                    } else {
                        _ = model.createProjectConnection()
                    }
                }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("新建项目") { _ = model.createProject() }
            }
            CommandGroup(after: .sidebar) {
                Button("切换侧边栏") {
                    NotificationCenter.default.post(name: .toggleQuietPaperSidebar, object: nil)
                }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("切换专注模式") {
                    NotificationCenter.default.post(name: .toggleQuietPaperFocusMode, object: nil)
                }
                    .keyboardShortcut("e", modifiers: [.command])
            }
            CommandMenu("笔记") {
                Button("立即保存") { model.forceSave() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("格式化 JSON") { model.formatJSON() }
                    .keyboardShortcut("j", modifiers: [.command, .option])
                Divider()
                Button("跳转到快捷页面 1") { postQuickJump(slot: 1) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("跳转到快捷页面 2") { postQuickJump(slot: 2) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("跳转到快捷页面 3") { postQuickJump(slot: 3) }
                    .keyboardShortcut("3", modifiers: [.command])
            }
        }
    }

    private func postQuickJump(slot: Int) {
        NotificationCenter.default.post(
            name: .jumpToQuietPaperQuickPage,
            object: nil,
            userInfo: ["slot": slot]
        )
    }
}

@MainActor
private final class QuietPaperAppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command),
                  !modifiers.contains(.shift),
                  !modifiers.contains(.option),
                  !modifiers.contains(.control) else {
                return event
            }

            // 数字键的字符值会随键盘布局变化，使用物理键位作为快捷跳转的兜底。
            if let slot = [18: 1, 19: 2, 20: 3][Int(event.keyCode)] {
                NotificationCenter.default.post(
                    name: .jumpToQuietPaperQuickPage,
                    object: nil,
                    userInfo: ["slot": slot]
                )
                return nil
            }

            guard let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            switch key {
            case "b":
                NotificationCenter.default.post(name: .toggleQuietPaperSidebar, object: nil)
                return nil
            case "e":
                NotificationCenter.default.post(name: .toggleQuietPaperFocusMode, object: nil)
                return nil
            case "1", "2", "3":
                let slot = Int(key) ?? 1
                NotificationCenter.default.post(
                    name: .jumpToQuietPaperQuickPage,
                    object: nil,
                    userInfo: ["slot": slot]
                )
                return nil
            default:
                return event
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
    }
}

extension Notification.Name {
    static let toggleQuietPaperSidebar = Notification.Name("QuietPaper.toggleSidebar")
    static let toggleQuietPaperFocusMode = Notification.Name("QuietPaper.toggleFocusMode")
    static let jumpToQuietPaperQuickPage = Notification.Name("QuietPaper.jumpToQuickPage")
}
