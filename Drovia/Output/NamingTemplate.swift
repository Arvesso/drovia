import Foundation

/// File naming for processed files.
enum NamingTemplate {
    static let defaultTemplate = "{name}-{action}"
    static let tokens = ["{name}", "{action}", "{date}"]

    /// Fills `{name}`, `{action}` and `{date}`. Falls back to `name` if the result would be empty.
    static func render(_ template: String, name: String, action: String, date: Date = .now) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let rendered = template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{action}", with: action)
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return rendered.isEmpty || rendered.hasPrefix(".") ? name : rendered
    }

    /// `base.ext`, or Finder-style `base 2.ext`, `base 3.ext`… when taken.
    static func uniqueFileName(base: String, fileExtension: String, isTaken: (String) -> Bool) -> String {
        func fileName(_ suffix: String) -> String {
            fileExtension.isEmpty ? base + suffix : "\(base)\(suffix).\(fileExtension)"
        }
        var candidate = fileName("")
        var counter = 2
        while isTaken(candidate) {
            candidate = fileName(" \(counter)")
            counter += 1
        }
        return candidate
    }
}
