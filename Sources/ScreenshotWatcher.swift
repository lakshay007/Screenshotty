import AppKit

/// Watches the folder macOS saves screenshots into and reports each new one.
final class ScreenshotWatcher: NSObject {
    enum State {
        case watching(URL)
        case unreadable(URL)
    }

    private(set) var state: State
    private let onScreenshot: (Screenshot) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []
    private let screencapturePrefs = UserDefaults(suiteName: "com.apple.screencapture")

    init(onScreenshot: @escaping (Screenshot) -> Void) {
        self.onScreenshot = onScreenshot
        self.state = .unreadable(Self.screenshotFolder())
        super.init()
        // Follow the folder if it is changed in the Screenshot app's Options menu.
        screencapturePrefs?.addObserver(self, forKeyPath: "location", options: [], context: nil)
    }

    deinit {
        screencapturePrefs?.removeObserver(self, forKeyPath: "location")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, Self.screenshotFolder() != self.folder else { return }
            self.start()
        }
    }

    var folder: URL {
        switch state {
        case .watching(let url), .unreadable(let url): return url
        }
    }

    var isWatching: Bool {
        if case .watching = state { return true }
        return false
    }

    /// (Re)starts watching the current screenshot folder.
    func start() {
        source?.cancel()
        source = nil

        let folder = Self.screenshotFolder()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            state = .unreadable(folder)
            log.error("cannot read \(folder.path, privacy: .public)")
            return
        }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            state = .unreadable(folder)
            log.error("cannot open \(folder.path, privacy: .public)")
            return
        }

        knownFiles = Set(names)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.isDisjoint(with: [.delete, .rename]) {
                self.scan()
            } else {
                self.start() // the folder itself was moved or removed
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        state = .watching(folder)
        log.info("watching \(folder.path, privacy: .public)")
    }

    private func scan() {
        let folder = self.folder
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let current = Set(names)
        let added = current.subtracting(knownFiles)
        knownFiles = current

        for name in added where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            guard Screenshot.imageExtensions.contains(url.pathExtension.lowercased()),
                  Self.wasJustCreated(url)
            else { continue }
            consider(url, attemptsLeft: 10)
        }
    }

    /// The screenshot marker and the image data can land a moment after the file appears, so retry briefly.
    private func consider(_ url: URL, attemptsLeft: Int) {
        if Self.isScreenCapture(url), let screenshot = Screenshot(url: url) {
            onScreenshot(screenshot)
        } else if attemptsLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.consider(url, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    /// macOS tags every screenshot it saves with this extended attribute.
    private static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// Filters out old screenshots that were merely moved (or restored from the Trash) into the folder.
    private static func wasJustCreated(_ url: URL) -> Bool {
        guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false }
        return abs(created.timeIntervalSinceNow) < 60
    }

    /// Where macOS saves screenshots: the `location` preference if it points at a folder, else the Desktop.
    static func screenshotFolder() -> URL {
        // `-watchFolder <path>` launch argument overrides the folder, for testing.
        let candidates = [
            UserDefaults.standard.string(forKey: "watchFolder"),
            UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
        ]
        for case let path? in candidates {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].standardizedFileURL
    }
}
