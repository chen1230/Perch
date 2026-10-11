import AppKit

/// Where Perch keeps its own files. The first launch moves the previous
/// folder across, so copied text and screenshots are not left behind.
enum AppFiles {
    private static let legacyBundle = "app.tendedero.Tendedero"
    private static let migratedKey = "migratedFromTendedero"

    static let root: URL = {
        migrateDefaults()
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let next = base.appendingPathComponent("Perch", isDirectory: true)
        let previous = base.appendingPathComponent("Tendedero", isDirectory: true)
        if fm.fileExists(atPath: previous.path), !fm.fileExists(atPath: next.path) {
            try? fm.moveItem(at: previous, to: next)
        }
        try? fm.createDirectory(at: next, withIntermediateDirectories: true)
        retargetCaptures(to: next.appendingPathComponent("Screenshots", isDirectory: true))
        return next
    }()

    static var screenshots: URL {
        root.appendingPathComponent("Screenshots", isDirectory: true)
    }

    static var textClips: URL {
        root.appendingPathComponent("text-clips.json")
    }

    /// Copies the previous app's preferences once. Later choices stay here.
    private static func migrateDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        let bundle = Bundle.main.bundleIdentifier ?? "app.perch.Perch"
        var merged = defaults.persistentDomain(forName: bundle) ?? [:]
        if let old = defaults.persistentDomain(forName: legacyBundle) {
            for (key, value) in old where merged[key] == nil {
                merged[key] = rewritePaths(value)
            }
        }
        merged[migratedKey] = true
        defaults.setPersistentDomain(merged, forName: bundle)
    }

    /// If captures were still being saved into the previous folder, point them here.
    private static func retargetCaptures(to folder: URL) {
        let domain = "com.apple.screencapture" as CFString
        let legacy = "/Tendedero/Screenshots"
        var changed = false
        for key in ["location", "location-screenshot", "location-screenrecording"] {
            guard let current = CFPreferencesCopyAppValue(key as CFString, domain) as? String else { continue }
            let path = (current as NSString).expandingTildeInPath
            guard path.contains(legacy) else { continue }
            CFPreferencesSetAppValue(key as CFString, folder.path as CFString, domain)
            changed = true
        }
        if changed { CFPreferencesAppSynchronize(domain) }
    }

    /// Saved screenshot paths still name the previous folder after the move.
    private static func rewritePaths(_ value: Any) -> Any {
        if let text = value as? String {
            return text.replacingOccurrences(of: "/Tendedero/", with: "/Perch/")
        }
        if let list = value as? [Any] {
            return list.map { rewritePaths($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { rewritePaths($0) }
        }
        if let data = value as? Data,
           let text = String(data: data, encoding: .utf8),
           text.contains("/Tendedero/") {
            return Data(text.replacingOccurrences(of: "/Tendedero/", with: "/Perch/").utf8)
        }
        return value
    }
}
