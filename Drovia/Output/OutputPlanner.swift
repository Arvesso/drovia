import Foundation

/// Decides where processed files go and reserves unique names, so parallel jobs never collide.
actor OutputPlanner {
    enum Location: Sendable {
        case nextToOriginal
        case folder(URL)
    }

    private let location: Location
    private let template: String
    private var reserved: Set<String> = []

    init(location: Location, template: String) {
        self.location = location
        self.template = template
    }

    /// Destination for the result of processing `source`.
    /// - Parameter action: name suffix for tools (e.g. "compressed"); `nil` keeps the name (conversions).
    func destination(for source: URL, action: String?, fileExtension: String) -> URL {
        let folder = folder(for: source)
        let name = source.deletingPathExtension().lastPathComponent
        let base = action.map { NamingTemplate.render(template, name: name, action: $0) } ?? name
        let fileName = NamingTemplate.uniqueFileName(base: base, fileExtension: fileExtension) { candidate in
            let path = folder.appendingPathComponent(candidate).path
            return reserved.contains(path) || FileManager.default.fileExists(atPath: path)
        }
        let url = folder.appendingPathComponent(fileName)
        reserved.insert(url.path)
        return url
    }

    private func folder(for source: URL) -> URL {
        switch location {
        case let .folder(url):
            return url
        case .nextToOriginal:
            // Files dropped from Safari, Mail etc. live in our temporary folder; put results in Downloads.
            if source.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
                return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            }
            return source.deletingLastPathComponent()
        }
    }
}
