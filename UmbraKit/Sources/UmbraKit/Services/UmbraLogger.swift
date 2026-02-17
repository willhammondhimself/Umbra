import os

public enum UmbraLogger {
    public static let auth = Logger(subsystem: "com.umbra.app", category: "auth")
    public static let sync = Logger(subsystem: "com.umbra.app", category: "sync")
    public static let database = Logger(subsystem: "com.umbra.app", category: "database")
    public static let session = Logger(subsystem: "com.umbra.app", category: "session")
    public static let blocking = Logger(subsystem: "com.umbra.app", category: "blocking")
    public static let social = Logger(subsystem: "com.umbra.app", category: "social")
    public static let general = Logger(subsystem: "com.umbra.app", category: "general")
}
