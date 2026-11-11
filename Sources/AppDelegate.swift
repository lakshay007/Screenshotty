import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher!
    private let previewPanel = PreviewPanelController()

    private let folderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let privacyItem = NSMenuItem(title: "Open Privacy Settings…",
                                         action: #selector(openPrivacySettings), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login",
                                       action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        watcher = ScreenshotWatcher { [weak self] screenshot in
            log.info("copied \(screenshot.url.lastPathComponent, privacy: .public)")
            screenshot.copyToClipboard()
            self?.previewPanel.show(screenshot)
        }
        watcher.start()
        enableLaunchAtLoginOnFirstRun()
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "Screenshotty")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(folderItem)
        menu.addItem(privacyItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenshotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Pick up folder access that was granted in System Settings since the last attempt.
        if !watcher.isWatching { watcher.start() }

        let folder = (watcher.folder.path as NSString).abbreviatingWithTildeInPath
        folderItem.title = watcher.isWatching ? "Watching \(folder)" : "No access to \(folder)"
        privacyItem.isHidden = watcher.isWatching
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Launch at login

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            log.info("launch at login turned \(enabled ? "on" : "off", privacy: .public)")
        } catch {
            log.error("could not change launch at login: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    /// Turns launch at login on once, for the installed copy only (not for builds run from the project folder).
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didEnableLaunchAtLogin"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key)
        else { return }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }
}
