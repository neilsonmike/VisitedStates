import Foundation

// MARK: - Logging Setup

extension AppDelegate {
    /// Configure application logging based on the current build configuration
    func configureLogging() {
        #if DEBUG
        // In debug builds, enable more verbose logging
        Logger.configure(logLevel: .debug, enabled: true)
        
        // Enable specific components (add as needed)
        Logger.enableLogging(for: "FactoidService")
        Logger.enableLogging(for: "NotificationService")
        Logger.enableLogging(for: "StateDetectionService")
        
        logger.info("Logging configured for DEBUG build")
        #else
        // In release builds, disable most logging
        Logger.configure(logLevel: .error, enabled: true)
        logger.info("Logging configured for RELEASE build")
        #endif
    }
}

// Example of how to use the Logger in a class
extension AppDelegate {
    // Create a logger for this class
    private var logger: Logger {
        return Logger.forClass(AppDelegate.self)
    }
    
    // Example logging methods
    func logAppLaunch() {
        logger.info("Application launched")
    }
    
    func logAppDidEnterBackground() {
        logger.info("Application entered background")
    }
    
    func logAppWillEnterForeground() {
        logger.info("Application will enter foreground")
    }
    
    func logAppDidBecomeActive() {
        logger.info("Application became active")
    }
    
    func logAppWillTerminate() {
        logger.info("Application will terminate")
    }
}