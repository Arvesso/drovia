import os

extension Logger {
    private static let subsystem = "com.arvesso.drovia"

    static let drag = Logger(subsystem: subsystem, category: "drag")
    static let wheel = Logger(subsystem: subsystem, category: "wheel")
}
