# Swift/AppKit Learning Notes

## What We Built

This is an **AppKit** application (not SwiftUI). AppKit is the older, more mature macOS framework.

### Key Differences:
- **AppKit**: Traditional macOS apps (what we're using)
- **SwiftUI**: Modern, declarative UI framework (newer, different syntax)

## UI Layout Changes Made

### 1. Full Screen Start
```swift
// Get the screen size
let screenRect = NSScreen.main?.visibleFrame

// Create window that fills the screen
window = NSWindow(contentRect: screenRect, ...)

// Set frame to maximize
window.setFrame(screenRect, display: true)
```

### 2. Toolbar (Highest Bar Position)

**Understanding macOS Window Hierarchy:**
```
┌─────────────────────────────────────┐
│  System Menu Bar (can't customize) │  ← Apple logo, app name, system menus
├─────────────────────────────────────┤
│  Title Bar                          │  ← Window title
│  TOOLBAR (← we added this!)         │  ← Customizable area for controls
├─────────────────────────────────────┤
│                                     │
│  Content View                       │  ← Your main app content
│  (Table goes here)                  │
│                                     │
└─────────────────────────────────────┘
```

The **toolbar** is the highest position you can put custom controls in your window.

### 3. How Toolbars Work in AppKit

**Step 1: Create toolbar in window**
```swift
let toolbar = NSToolbar(identifier: "MainToolbar")
toolbar.delegate = self
window.toolbar = toolbar
```

**Step 2: Implement NSToolbarDelegate**
```swift
extension TableViewController: NSToolbarDelegate {
    // This creates each toolbar item
    func toolbar(_ toolbar: NSToolbar, 
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    
    // This defines which items appear by default
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
}
```

**Step 3: Define custom identifier**
```swift
extension NSToolbarItem.Identifier {
    static let urlSearch = NSToolbarItem.Identifier("URLSearch")
}
```

### 4. Key AppKit Concepts Used

**NSViewController**: Manages a view and its subviews
**NSWindow**: The actual window container
**NSToolbar**: Toolbar area below title bar
**NSSearchField**: macOS-style search box with built-in clear button
**NSTableView**: Native table display (like Excel)
**NSScrollView**: Provides scrolling for content

## Result

✅ App now starts **maximized/full screen**
✅ URL bar is in the **toolbar** (highest position possible)
✅ Table fills the entire content area
✅ Clean, professional macOS appearance

## Tips for Learning Swift/AppKit

1. **AppKit is object-oriented** - uses classes, delegates, and target-action patterns
2. **SwiftUI is declarative** - describes what you want, not how to build it
3. Most macOS apps still use AppKit for complex UIs
4. Apple's documentation: https://developer.apple.com/documentation/appkit
