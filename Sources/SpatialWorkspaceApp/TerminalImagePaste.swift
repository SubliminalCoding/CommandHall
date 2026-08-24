import AppKit
import Foundation

/// Turns a pasted image (a screenshot on the clipboard, or a copied image file)
/// into a file path that can be handed to a CLI agent. Screenshots become PNGs
/// on the Fleet4TB SSD (the mini is disk-tight), and the returned path is
/// shell-quoted so it can be dropped straight onto a command line.
enum TerminalImagePaste {
    /// If the pasteboard holds an image, materialize it to a file and return a
    /// shell-safe path. Returns nil when there is no image (so text paste can
    /// fall through to normal handling).
    static func pastedImagePath() -> String? {
        let pasteboard = NSPasteboard.general

        // A copied image *file* — use it in place, don't duplicate it.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let file = urls.first(where: { isImagePath($0.path) }) {
            return shellQuote(file.path)
        }

        guard let png = pngData(from: pasteboard) else { return nil }
        let directory = pasteDirectory()
        let name = "paste-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 1000...9999)).png"
        let destination = directory.appendingPathComponent(name)
        do {
            try png.write(to: destination)
            return shellQuote(destination.path)
        } catch {
            return nil
        }
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff) { return pngFromTIFF(tiff) }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let tiff = images.first?.tiffRepresentation {
            return pngFromTIFF(tiff)
        }
        return nil
    }

    private static func pngFromTIFF(_ tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// Prefer the Fleet4TB SSD; fall back to a temp dir if it isn't mounted.
    private static func pasteDirectory() -> URL {
        let fileManager = FileManager.default
        let fleet = URL(fileURLWithPath: "/Volumes/Fleet4TB/pasted-images", isDirectory: true)
        if fileManager.fileExists(atPath: "/Volumes/Fleet4TB") {
            try? fileManager.createDirectory(at: fleet, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fleet.path) { return fleet }
        }
        let temp = fileManager.temporaryDirectory.appendingPathComponent("spatial-pastes", isDirectory: true)
        try? fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    private static func isImagePath(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"]
            .contains((path as NSString).pathExtension.lowercased())
    }

    /// Quote a path for a POSIX shell only when it contains anything unusual.
    static func shellQuote(_ path: String) -> String {
        if path.range(of: "[^A-Za-z0-9._/-]", options: .regularExpression) == nil { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
