import AppKit
import SwiftUI

@MainActor
class VPhoneFileWindowController {
    private var window: NSWindow?
    private var model: VPhoneFileBrowserModel?
    private var eventMonitor: Any?

    func showWindow(control: VPhoneControl) {
        // Reuse existing window
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = VPhoneFileBrowserModel(control: control)
        self.model = model

        let view = VPhoneFileBrowserView(model: model)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Files"
        window.subtitle = "vphone"
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 500, height: 300)
        window.center()
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        // Add toolbar so the unified title bar shows
        let toolbar = NSToolbar(identifier: "vphone-files-toolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.makeKeyAndOrderFront(nil)
        self.window = window

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                window.performClose(nil)
                return nil
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowWillCloseNotification()
            }
        }
    }

    private func handleWindowWillCloseNotification() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        window = nil
        model = nil
    }
}
