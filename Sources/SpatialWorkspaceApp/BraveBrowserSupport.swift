import AppKit
import Foundation

enum BraveBrowserSupport {
    static let bundleIdentifier = "com.brave.Browser"
    static let uBlockOriginExtensionID = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    static let downloadURL = URL(string: "https://brave.com/download/")!
    static let uBlockOriginStoreURL = URL(
        string: "https://chromewebstore.google.com/detail/ublock-origin/\(uBlockOriginExtensionID)"
    )!
    static let blankPageURL = URL(string: "https://search.brave.com/")!

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var isUBlockOriginInstalled: Bool {
        let profilesRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        return profiles.contains { profile in
            let profileName = profile.lastPathComponent
            guard profileName == "Default" || profileName.hasPrefix("Profile ") else { return false }
            return FileManager.default.fileExists(
                atPath: profile
                    .appendingPathComponent("Extensions", isDirectory: true)
                    .appendingPathComponent(uBlockOriginExtensionID, isDirectory: true)
                    .path
            )
        }
    }

    static func destinationURL(for address: String?) -> URL {
        guard let address else { return blankPageURL }
        let normalized = BrowserAddress.normalize(address)
        guard normalized != "about:blank", let url = URL(string: normalized) else { return blankPageURL }
        return url
    }

    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSWorkspace.shared.open(downloadURL)
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
        return true
    }
}
