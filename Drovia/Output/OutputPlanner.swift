import Foundation

/// Decides where processed files go and reserves unique names, so parallel jobs never collide.
actor OutputPlanner {
    enum Location: Sendable {
        case nextToOriginal
        case folder(URL)
    }

    let location: Location
    let template: String
    /// Intermediate files (from earlier recipe steps) mapped to the original each came from,
    /// so results land next to the original rather than in a temporary folder.
    private let originals: [URL: URL]
    private var reserved: Set<String> = []

    init(location: Location, template: String, originals: [URL: URL] = [:]) {
        self.location = location
        self.template = template
        self.originals = originals
    }

    /// Destination for the result of processing `source`.
    /// - Parameter action: name suffix for tools (e.g. "compressed"); `nil` keeps the name (conversions).
    func destination(for source: URL, action: String?, fileExtension: String) -> URL {
        let folder = folder(for: source)
        let name = source.deletingPathExtension().lastPathComponent
        let base = action.map { NamingTemplate.render(template, name: name, action: $0) } ?? name
        let fileName = NamingTemplate.uniqueFileName(base: base, fileExtension: fileExtension) { candidate in
            let path = folder.appendingPathComponent(candidate).path
            return reserved.contains(Self.key(path)) || FileManager.default.fileExists(atPath: path)
        }
        let url = folder.appendingPathComponent(fileName)
        reserved.insert(Self.key(url.path))
        return url
    }

    /// Volumes are usually case-insensitive and ignore Unicode normalization, so "Photo.webp" and
    /// "photo.webp" are one file there.
    private static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func folder(for source: URL) -> URL {
        let source = originals[source] ?? source
        switch location {
        case let .folder(url):
            return url
        case .nextToOriginal:
            // Files dropped from Safari, Mail etc. live in our temporary folder; put results in Downloads.
            if source.path.hasPrefix(DroppedFiles.temporaryRoot.path) {
                return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            }
            return source.deletingLastPathComponent()
        }
    }
}
