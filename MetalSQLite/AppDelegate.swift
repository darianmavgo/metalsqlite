import Cocoa
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var viewController: TableViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("=== ApplicationDidFinishLaunching ===")
        
        // Set activation policy to show in dock and allow focus
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Setup application menu
        setupApplicationMenu()
        
        // Get screen size for initial window
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        
        // Create window with full screen support
        window = NSWindow(
            contentRect: screenRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Metal SQLite Viewer"
        window.collectionBehavior = [.fullScreenPrimary]  // Enable full screen
        
        NSLog("Window created: %@", window)
        
        // Create view controller
        viewController = TableViewController()
        window.contentViewController = viewController
        
        // Setup toolbar
        viewController.setupToolbar(for: window)
        
        NSLog("View controller set")
        
        // Show and activate window
        window.makeKeyAndOrderFront(nil)
        
        // Maximize to full visible frame (allows system bar to stay visible at top)
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }
        
        // Activate app to bring window to front
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        NSLog("Window should now be visible")
        
        // Load default database
        let defaultDB = "/Users/darianhickman/Documents/Index.sqlite"
        viewController.loadDatabase(path: defaultDB, table: "tb0")
        
        NSLog("=== Initialization complete ===")
    }
    
    var queryInfoMenuItem: NSMenuItem!
    var progressMenuItem: NSMenuItem!
    
    func setupApplicationMenu() {
        let mainMenu = NSMenu()
        
        // MetalSQLite menu (app menu)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        // Quit menu item with Cmd+Q
        let quitMenuItem = NSMenuItem(
            title: "Quit MetalSQLite",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitMenuItem)
        
        // Row Progress menu (dynamic)
        progressMenuItem = NSMenuItem()
        progressMenuItem.title = "Rows: 0"
        mainMenu.addItem(progressMenuItem)
        
        // Query Info menu (dynamic)
        queryInfoMenuItem = NSMenuItem()
        queryInfoMenuItem.title = "No Query"
        mainMenu.addItem(queryInfoMenuItem)
        
        let queryInfoMenu = NSMenu()
        queryInfoMenuItem.submenu = queryInfoMenu
        
        // Placeholder items (will be updated dynamically)
        queryInfoMenu.addItem(NSMenuItem(title: "No data loaded", action: nil, keyEquivalent: ""))
        
        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func updateProgressMenu(rowsLoaded: Int) {
        DispatchQueue.main.async {
            self.progressMenuItem.title = "Rows: \(rowsLoaded)"
        }
    }
    
    func updateQueryInfoMenu(datasetPath: String, table: String, columns: [String], limit: String?, total: Int) {
        // Update menu title to show current database/table
        let dbName = (datasetPath as NSString).lastPathComponent
        queryInfoMenuItem.title = "\(dbName)/\(table)"
        
        // Clear existing items
        queryInfoMenuItem.submenu?.removeAllItems()
        
        // Add DatasetPath
        let datasetPathItem = NSMenuItem(title: "DatasetPath: \(datasetPath)", action: nil, keyEquivalent: "")
        datasetPathItem.isEnabled = false
        queryInfoMenuItem.submenu?.addItem(datasetPathItem)
        
        // Add ColumnSetPath (Table + Columns info)
        let columnSetPathItem = NSMenuItem(title: "ColumnSetPath: \(table)", action: nil, keyEquivalent: "")
        columnSetPathItem.isEnabled = false
        queryInfoMenuItem.submenu?.addItem(columnSetPathItem)
        
        queryInfoMenuItem.submenu?.addItem(NSMenuItem.separator())
        
        // Add columns
        let columnsItem = NSMenuItem(title: "Columns (\(columns.count)): \(columns.joined(separator: ", "))", action: nil, keyEquivalent: "")
        columnsItem.isEnabled = false
        queryInfoMenuItem.submenu?.addItem(columnsItem)
        
        // Add limit
        if let limit = limit {
            let limitItem = NSMenuItem(title: "Query Params: \(limit)", action: nil, keyEquivalent: "")
            limitItem.isEnabled = false
            queryInfoMenuItem.submenu?.addItem(limitItem)
        }
        
        // Add total
        let totalItem = NSMenuItem(title: "Total Rows: \(total)", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        queryInfoMenuItem.submenu?.addItem(totalItem)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
