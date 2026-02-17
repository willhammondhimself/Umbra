import os

public enum TetherLogger {
    public static let auth = Logger(subsystem: "com.tether.app", category: "auth")
    public static let sync = Logger(subsystem: "com.tether.app", category: "sync")
    public static let database = Logger(subsystem: "com.tether.app", category: "database")
    public static let session = Logger(subsystem: "com.tether.app", category: "session")
    public static let blocking = Logger(subsystem: "com.tether.app", category: "blocking")
    public static let social = Logger(subsystem: "com.tether.app", category: "social")
    public static let general = Logger(subsystem: "com.tether.app", category: "general")
    public static let calendar = Logger(subsystem: "com.tether.app", category: "calendar")
}
