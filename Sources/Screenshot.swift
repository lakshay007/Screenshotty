import AppKit

/// A screenshot file loaded into memory, so it stays pasteable after the file is deleted.
struct Screenshot {
    let url: URL
    let pngData: Data
    let image: NSImage

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp"]

    /// Returns nil while the file is still being written or if it isn't a decodable image.
    init?(url: URL) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let rep = NSBitmapImageRep(data: data),
              let image = NSImage(data: data)
        else { return nil }

        if url.pathExtension.lowercased() == "png" {
            pngData = data
        } else if let converted = rep.representation(using: .png, properties: [:]) {
            pngData = converted
        } else {
            return nil
        }
        self.url = url
        self.image = image
    }

    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    /// Moves the file to the Trash (recoverable). Returns false if it could not be moved.
    @discardableResult
    func moveToTrash() -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            log.error("could not trash \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
