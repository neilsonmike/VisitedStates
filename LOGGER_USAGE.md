# Logger Usage Guide

This document shows how to use the new centralized Logger throughout the app.

## Basic Usage

1. Create a logger for your class:

```swift
private var logger: Logger {
    return Logger.forClass(YourClassName.self)
}
```

2. Use it to log messages at different levels:

```swift
logger.debug("This is detailed diagnostic information")
logger.info("This is general information about application flow")
logger.warning("This is a warning that might require attention")
logger.error("This is an error that needs to be addressed")
```

## Converting Existing Code

### Before:

```swift
// Old approach with debug flags and print statements
private let debug = true
private func logDebug(_ message: String) {
    if debug {
        print("FactoidService: \(message)")
    }
}

// Usage
logDebug("Fetching factoids from Google Sheets")
```

### After:

```swift
// New approach with Logger
private var logger: Logger {
    return Logger.forClass(FactoidService.self)
}

// Usage
logger.debug("Fetching factoids from Google Sheets")
```

## Controlling Logging

Logging is configured in `AppDelegate`:

```swift
func configureLogging() {
    #if DEBUG
    // In debug builds, enable more verbose logging
    Logger.configure(logLevel: .debug, enabled: true)
    Logger.enableLogging(for: "FactoidService")
    #else
    // In release builds, disable most logging
    Logger.configure(logLevel: .error, enabled: true)
    #endif
}
```

## Benefits

1. **Consistent format** across the app
2. **Centralized control** over what gets logged
3. **Component-specific filtering** to focus on areas of interest
4. **Log levels** to control verbosity
5. **Build configuration awareness** to automatically reduce logging in production

## Production Logging

For production, the logger is configured to only show errors, but this can be adjusted as needed:

```swift
// Production config (in AppDelegate)
Logger.configure(logLevel: .error, enabled: true)
```

## Example Implementation

See `AppDelegateLogger.swift` for a complete example of how to set up and use the logging system.