# Objective
Update the main navigation/toolbar architecture in the current project to support the new iOS 26+ Liquid Glass Native Toolbar, while preserving the existing toolbar implementation as a fallback for iOS 17+.

## Context
- **Project Folder:** [Insert relevant file paths/views here, e.g., `MainView.swift`, `AppNavigation.swift`]
- **Current State:** The app currently uses a custom/standard toolbar built for iOS 17+.
- **Target State:** The app must dynamically switch between the iOS 26+ "Liquid Glass" toolbar and the legacy iOS 17+ toolbar based on the user's device OS version.

## Requirements
1. **Conditional Availability:** Use Swift's `#available` attribute to check for iOS 26.0. 
2. **Liquid Glass Implementation (iOS 26+):** - Implement the Native Liquid Glass Toolbar for devices running iOS 26 or newer.
   - Apply the correct materials, environment modifiers, or native initializers specific to the Liquid Glass API.
3. **Fallback Implementation (iOS 17 - 25):** - Retain the exact existing toolbar code for the `else` branch. Do not refactor the legacy toolbar's design or logic.
4. **Clean Code:** Ensure the conditional logic is handled gracefully, preferably abstracting the toolbar into a custom ViewModifier or separate View extension if it gets too bulky.

## Expected Code Structure Example
Please structure the view modifiers roughly like this:

```swift
if #available(iOS 26.0, *) {
    // Apply new Liquid Glass Toolbar logic here
    content
        .toolbar {
            // iOS 26+ specific implementation
        }
} else {
    // Apply existing iOS 17+ toolbar logic here
    content
        .toolbar {
            // Legacy implementation
        }
}


