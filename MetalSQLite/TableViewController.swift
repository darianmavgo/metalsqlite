import Cocoa
import MetalKit

class TableViewController: NSViewController {
    var serverURL: String {
        // Read port from file written by Go server
        let portFile = "/tmp/metalsqlite.port"
        if let portData = try? String(contentsOfFile: portFile, encoding: .utf8),
           let port = Int(portData.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return "http://[::1]:\(port)"
        }
        return "http://[::1]:8080" // Fallback
    }
    var currentBanquetURL = ""
    var tableData: [[Any]] = []
    var columns: [ColumnInfo] = []
    
    var urlBar: NSTextField!
    var tableView: NSTableView!
    var scrollView: NSScrollView!
    var statusLabel: NSTextField!
    var isFirstBatch = true
    
    struct ColumnInfo: Codable {
        let name: String
        let type: String
    }
    
    struct QueryResponse: Codable {
        let columns: [ColumnInfo]?
        let rows: [[AnyCodable]]?
        let total: Int
        let error: String?
    }
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        setupUI()
    }
    
    func setupUI() {
        // Status label at bottom
        statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.frame = NSRect(x: 20, y: 10, width: Int(view.bounds.width) - 40, height: 20)
        statusLabel.autoresizingMask = [.width]
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)
        
        // Table view fills entire space (toolbar will be outside this view)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 40, width: Int(view.bounds.width), height: Int(view.bounds.height) - 40))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        
        tableView = NSTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing  // Disable auto-resizing to maintain calculated widths
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }
    
    func setupToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        
        window.toolbar = toolbar
        window.titleVisibility = .hidden  // Hide title to give more space
    }
    
    func loadDatabase(path: String, table: String) {
        currentBanquetURL = "\(path)/\(table)?limit=100"
        urlBar.stringValue = currentBanquetURL
        executeQueryWithURL(currentBanquetURL)
    }
    
    @objc func executeQuery() {
        let url = urlBar.stringValue
        if url.isEmpty {
            statusLabel.stringValue = "Error: Enter a Banquet URL"
            return
        }
        executeQueryWithURL(url)
    }
    
    var streamingProvider: StreamingProvider?
    
    func executeQueryWithURL(_ banquetURL: String) {
        logToSharedFile("Starting query: \(banquetURL)")
        statusLabel.stringValue = "Executing query (streaming)..."
        
        guard let url = URL(string: "\(serverURL)/query") else {
            statusLabel.stringValue = "Error: Invalid server URL"
            return
        }
        
        // Reset data
        tableData = []
        columns = []
        isFirstBatch = true
        tableView.reloadData()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["banquet_url": banquetURL]
        request.httpBody = try? JSONEncoder().encode(body)
        
        // Use custom session for streaming
        streamingProvider = StreamingProvider()
        streamingProvider?.onHeaderReceived = { [weak self] columns, total in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.columns = columns
                self.logToSharedFile("Header received: \(columns.count) columns, \(total) total rows expected")
                self.updateTableColumns()
                self.statusLabel.stringValue = "Streaming... (Total: \(total))"
            }
        }
        streamingProvider?.onRowsReceived = { [weak self] rows in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.tableData.append(contentsOf: rows)
                
                if self.isFirstBatch {
                    self.isFirstBatch = false
                    
                    // Log first page info
                    let columnNames = self.columns.map { $0.name }.joined(separator: ", ")
                    self.logToSharedFile("=== First Page Received ===")
                    self.logToSharedFile("Rows in page: \(rows.count)")
                    self.logToSharedFile("Columns: [\(columnNames)]")
                    
                    // Update table data and reload to ensure cells exist for measurement
                    self.tableView.reloadData()
                    
                    // Size to fit
                    self.tableView.tableColumns.forEach { $0.sizeToFit() }
                    
                    // Log results
                    let results = self.tableView.tableColumns.map { "\($0.title): \($0.width)" }.joined(separator: ", ")
                    self.logToSharedFile("Widths after sizeToFit(): \(results)")
                    self.logToSharedFile("===========================")
                } else {
                    self.tableView.reloadData()
                }
                
                let rowsCount = self.tableData.count
                self.statusLabel.stringValue = "Loaded \(rowsCount) rows..."
                
                // Update menu bar progress
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.updateProgressMenu(rowsLoaded: rowsCount)
                }
            }
        }
        streamingProvider?.onComplete = { [weak self] total in
            DispatchQueue.main.async {
                self?.statusLabel.stringValue = "Done! Loaded \(self?.tableData.count ?? 0) rows."
                // Update menu with final info
                if let self = self {
                    let dummyResponse = QueryResponse(columns: self.columns, rows: nil, total: total, error: nil)
                    self.updateMenuWithQueryInfo(banquetURL: banquetURL, response: dummyResponse)
                }
            }
        }
        streamingProvider?.onError = { [weak self] errorMsg in
            DispatchQueue.main.async {
                self?.statusLabel.stringValue = "Error: \(errorMsg)"
            }
        }
        
        let session = URLSession(configuration: .default, delegate: streamingProvider, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
    }
    func updateTableColumns() {
        // Remove existing columns
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
        
        let minColumnWidth = view.bounds.width * 0.01
        
        // Add new columns
        for columnInfo in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnInfo.name))
            column.title = columnInfo.name
            column.minWidth = minColumnWidth
            column.width = 150 // Initial width, will be updated by calculateAndSetColumnWidths
            tableView.addTableColumn(column)
        }
    }
    
    func logToSharedFile(_ message: String) {
        print("[UI] \(message)")
    }
    
    func updateMenuWithQueryInfo(banquetURL: String, response: QueryResponse) {
        // Basic parsing of Banquet URL to get DatasetPath and Table info
        // Example: /Users/darianhickman/Documents/Index.sqlite/tb0?limit=100
        
        let urlParts = banquetURL.components(separatedBy: "?")
        let pathPart = urlParts[0]
        let queryParams = urlParts.count > 1 ? urlParts[1] : nil
        
        let pathComponents = pathPart.components(separatedBy: "/")
        
        // Find the sqlite file in the path
        var datasetPath = ""
        var table = ""
        
        for (index, component) in pathComponents.enumerated() {
            if component.hasSuffix(".sqlite") {
                datasetPath = pathComponents[0...index].joined(separator: "/")
                if index + 1 < pathComponents.count {
                    table = pathComponents[index + 1]
                }
                break
            }
        }
        
        if datasetPath.isEmpty {
            datasetPath = pathPart
        }
        
        if table.isEmpty {
            table = "tb0" // Default
        }
        
        let columnNames = columns.map { $0.name }
        
        DispatchQueue.main.async {
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.updateQueryInfoMenu(
                    datasetPath: datasetPath,
                    table: table,
                    columns: columnNames,
                    limit: queryParams,
                    total: response.total
                )
            }
        }
    }
}

extension TableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableData.count
    }
}

extension TableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: column) else {
            return nil
        }
        
        // Safety check for row and column index
        guard row < tableData.count, columnIndex < tableData[row].count else {
            return nil
        }
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("Cell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
        
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier
            let textField = NSTextField()
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            
            // No wrap and clip text
            textField.lineBreakMode = .byClipping
            textField.cell?.wraps = false
            textField.cell?.isScrollable = false
            textField.maximumNumberOfLines = 1
            
            cell?.addSubview(textField)
            cell?.textField = textField
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        let value = tableData[row][columnIndex]
        cell?.textField?.stringValue = "\(value)"
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first,
              let columnIdentifier = sortDescriptor.key else {
            return
        }
        
        // Build new Banquet URL with sort
        let prefix = sortDescriptor.ascending ? "+" : "-"
        var newURL = currentBanquetURL
        
        // Simple implementation: append sort to URL
        if newURL.contains("/+") || newURL.contains("/-") {
            // Replace existing sort  (simplified)
            let parts = newURL.components(separatedBy: "?")
            let pathParts = parts[0].components(separatedBy: "/")
            var filteredParts = pathParts.filter { !$0.hasPrefix("+") && !$0.hasPrefix("-") }
            filteredParts.append("\(prefix)\(columnIdentifier)")
            newURL = filteredParts.joined(separator: "/")
            if parts.count > 1 {
                newURL += "?" + parts[1]
            }
        } else {
            newURL += "/\(prefix)\(columnIdentifier)"
        }
        
        urlBar.stringValue = newURL
        executeQueryWithURL(newURL)
    }
}

// Helper for decoding heterogeneous JSON arrays
struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = ""
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Toolbar Delegate
extension TableViewController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        if itemIdentifier == .urlSearch {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "" // Remove "Search" label that wraps
            item.paletteLabel = "URL / Query"
            
            let searchField = NSSearchField()
            searchField.placeholderString = "Index.sqlite/tb0?limit=100"
            searchField.target = self
            searchField.action = #selector(executeQuery)
            
            // Set 3x larger width (taking into account the screen width)
            // Instead of flexible, we set a large preferred width
            searchField.translatesAutoresizingMaskIntoConstraints = false
            searchField.widthAnchor.constraint(equalToConstant: 800).isActive = true 
            
            item.view = searchField
            urlBar = searchField
            
            return item
        }
        
        if itemIdentifier == .queryButton {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = ""  // No text label
            item.paletteLabel = "Execute Query"
            
            // Emoji button - use 🔍 magnifying glass
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
            button.title = "🔍"
            button.font = NSFont.systemFont(ofSize: 18)
            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(executeQuery)
            button.toolTip = "Execute Query"  // Helpful tooltip
            
            item.view = button
            return item
        }
        
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.urlSearch, .queryButton]  // Search item will auto-expand
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.urlSearch, .queryButton, .flexibleSpace, .space]
    }
}

// MARK: - Streaming
class StreamingProvider: NSObject, URLSessionDataDelegate {
    var onHeaderReceived: (([TableViewController.ColumnInfo], Int) -> Void)?
    var onRowsReceived: (([[Any]]) -> Void)?
    var onComplete: ((Int) -> Void)?
    var onError: ((String) -> Void)?
    
    private var buffer = Data()
    private var totalRows = 0
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        
        // Process NDJSON (lines)
        while let range = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound)
            
            if lineData.isEmpty { continue }
            
            do {
                let decoder = JSONDecoder()
                let chunk = try decoder.decode(TableViewController.QueryResponse.self, from: lineData)
                
                if let error = chunk.error {
                    onError?(error)
                    continue
                }
                
                if let cols = chunk.columns {
                    onHeaderReceived?(cols, chunk.total)
                }
                
                if let rows = chunk.rows {
                    totalRows += rows.count
                    let mappedRows = rows.map { $0.map { $0.value } }
                    onRowsReceived?(mappedRows)
                }
            } catch {
                print("Failed to decode chunk: \(error)")
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onError?(error.localizedDescription)
        } else {
            onComplete?(totalRows)
        }
    }
}

// MARK: - Toolbar Item Identifiers
extension NSToolbarItem.Identifier {
    static let urlSearch = NSToolbarItem.Identifier("URLSearch")
    static let queryButton = NSToolbarItem.Identifier("QueryButton")
}

