import Foundation

/// Simple logging utility for the app that provides consistent logging across components
class Logger {
    /// Log levels allow filtering of messages
    enum Level: Int {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        
        var prefix: String {
            switch self {
            case .debug: return "📋"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    /// Determines what level of logs should be displayed
    private static var globalLogLevel: Level = .info
    
    /// Enables or disables all logging
    private static var loggingEnabled: Bool = false
    
    /// Tracks components that should have logging enabled
    private static var enabledComponents: Set<String> = []
    
    /// Configure the logging system
    static func configure(logLevel: Level = .info, enabled: Bool = false) {
        globalLogLevel = logLevel
        loggingEnabled = enabled
    }
    
    /// Enable logging for a specific component
    static func enableLogging(for component: String) {
        enabledComponents.insert(component)
    }
    
    /// Disable logging for a specific component
    static func disableLogging(for component: String) {
        enabledComponents.remove(component)
    }
    
    /// The component name for this logger instance
    private let component: String
    
    /// Initialize a new logger for a component
    init(component: String) {
        self.component = component
    }
    
    /// Log a debug message
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    /// Log an info message
    func info(_ message: String) {
        log(message, level: .info)
    }
    
    /// Log a warning message
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    /// Log an error message
    func error(_ message: String) {
        log(message, level: .error)
    }
    
    /// Internal logging implementation
    private func log(_ message: String, level: Level) {
        // Only log if global logging is enabled and component is enabled
        guard Logger.loggingEnabled, 
              (Logger.enabledComponents.contains(component) || Logger.enabledComponents.contains("all")),
              level.rawValue >= Logger.globalLogLevel.rawValue else {
            return
        }
        
        // Format: [Level] Component: Message
        print("\(level.prefix) [\(component)] \(message)")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Create a logger for a class type
    static func forClass(_ anyClass: AnyClass) -> Logger {
        let className = String(describing: anyClass)
        return Logger(component: className)
    }
    
    /// Enable all logging (for development/debugging)
    static func enableAllLogging(atLevel level: Level = .debug) {
        configure(logLevel: level, enabled: true)
        enableLogging(for: "all")
    }
    
    /// Disable all logging (for production)
    static func disableAllLogging() {
        configure(logLevel: .error, enabled: false)
        enabledComponents.removeAll()
    }
}