package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"

	"github.com/darianhickman/banquet"
	_ "modernc.org/sqlite"
)

type QueryRequest struct {
	BanquetURL string `json:"banquet_url"`
}

type QueryResponse struct {
	Columns []ColumnInfo    `json:"columns"`
	Rows    [][]interface{} `json:"rows"`
	Total   int             `json:"total"`
	Error   string          `json:"error,omitempty"`
}

type ColumnInfo struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type SchemaResponse struct {
	Columns []ColumnInfo `json:"columns"`
	Error   string       `json:"error,omitempty"`
}

var dbCache = make(map[string]*sql.DB)

func main() {
	banquet.SetVerbose(true)

	http.HandleFunc("/query", handleQuery)
	http.HandleFunc("/schema/", handleSchema)
	http.HandleFunc("/health", handleHealth)

	// Use random high port (50000-60000)
	port := os.Getenv("PORT")
	if port == "" {
		// Pick random port
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Fatal(err)
		}
		defer listener.Close()

		actualPort := listener.Addr().(*net.TCPAddr).Port
		// Ensure it's in high range
		if actualPort < 50000 {
			actualPort = 50000 + (actualPort % 10000)
		}
		listener.Close()

		port = fmt.Sprintf("%d", actualPort)

		// Write port to file for client to discover
		portFile := "/tmp/metalsqlite.port"
		if err := os.WriteFile(portFile, []byte(port), 0644); err != nil {
			log.Printf("Warning: Could not write port file: %v", err)
		} else {
			log.Printf("Port written to %s", portFile)
		}
	}

	log.Printf("Starting Metal SQLite server on port %s", port)
	log.Fatal(http.ListenAndServe("[::1]:"+port, corsMiddleware(http.DefaultServeMux)))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req QueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendError(w, fmt.Sprintf("Invalid request: %v", err))
		return
	}

	log.Printf("Parsing Banquet URL: %s", req.BanquetURL)

	// Parse Banquet URL
	b, err := banquet.ParseBanquet(req.BanquetURL)
	if err != nil {
		sendError(w, fmt.Sprintf("Failed to parse Banquet URL: %v", err))
		return
	}

	// Resolve database path
	dbPath := b.DataSetPath
	if dbPath != "" && dbPath[0] != '/' {
		dbPath = "/" + dbPath
	}

	// Open database
	db, err := getDB(dbPath)
	if err != nil {
		sendError(w, fmt.Sprintf("Failed to open database: %v", err))
		return
	}

	// Build SQL query
	query, args := buildQuery(b)
	log.Printf("Executing SQL: %s with args: %v", query, args)

	// Get total count first (needed for UI)
	total := 0
	if b.Table != "" {
		countQuery := fmt.Sprintf("SELECT COUNT(*) FROM %s", b.Table)
		if b.Where != "" {
			countQuery += " WHERE " + b.Where
		}
		db.QueryRow(countQuery).Scan(&total)
	}

	// Execute query
	rows, err := db.Query(query, args...)
	if err != nil {
		sendError(w, fmt.Sprintf("Query failed: %v", err))
		return
	}
	defer rows.Close()

	// Get columns
	columnNames, _ := rows.Columns()
	columnTypes, _ := rows.ColumnTypes()
	columns := make([]ColumnInfo, len(columnNames))
	for i, name := range columnNames {
		columns[i] = ColumnInfo{
			Name: name,
			Type: columnTypes[i].DatabaseTypeName(),
		}
	}

	// Setup streaming response
	w.Header().Set("Content-Type", "application/x-ndjson")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)

	flusher, ok := w.(http.Flusher)
	encoder := json.NewEncoder(w)

	// Send header chunk
	encoder.Encode(QueryResponse{
		Columns: columns,
		Total:   total,
	})
	if ok {
		flusher.Flush()
	}

	// Stream rows in chunks
	const chunkSize = 64 * 1024 // ~64KB chunks
	var currentChunk [][]interface{}
	approxSize := 0

	for rows.Next() {
		values := make([]interface{}, len(columnNames))
		valuePtrs := make([]interface{}, len(columnNames))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			log.Printf("Error scanning row: %v", err)
			break
		}

		// Convert bytes to string
		for i, v := range values {
			if b, ok := v.([]byte); ok {
				values[i] = string(b)
			}
		}

		currentChunk = append(currentChunk, values)
		// Estimate size for chunking (very rough)
		approxSize += 100 // Average row overhead

		if approxSize >= chunkSize {
			encoder.Encode(QueryResponse{Rows: currentChunk})
			if ok {
				flusher.Flush()
			}
			currentChunk = nil
			approxSize = 0
		}
	}

	// Final chunk
	if len(currentChunk) > 0 {
		encoder.Encode(QueryResponse{Rows: currentChunk})
		if ok {
			flusher.Flush()
		}
	}
}

func handleSchema(w http.ResponseWriter, r *http.Request) {
	// Extract table name from path
	table := r.URL.Path[len("/schema/"):]
	if table == "" {
		sendError(w, "Table name required")
		return
	}

	// Get database path from query parameter
	dbPath := r.URL.Query().Get("db")
	if dbPath == "" {
		sendError(w, "Database path required (db query parameter)")
		return
	}

	db, err := getDB(dbPath)
	if err != nil {
		sendError(w, fmt.Sprintf("Failed to open database: %v", err))
		return
	}

	// Query schema
	query := fmt.Sprintf("PRAGMA table_info(%s)", table)
	rows, err := db.Query(query)
	if err != nil {
		sendError(w, fmt.Sprintf("Failed to get schema: %v", err))
		return
	}
	defer rows.Close()

	var columns []ColumnInfo
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull, pk int
		var dfltValue interface{}

		if err := rows.Scan(&cid, &name, &colType, &notNull, &dfltValue, &pk); err != nil {
			sendError(w, fmt.Sprintf("Failed to scan schema: %v", err))
			return
		}

		columns = append(columns, ColumnInfo{
			Name: name,
			Type: colType,
		})
	}

	response := SchemaResponse{
		Columns: columns,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func getDB(path string) (*sql.DB, error) {
	// Check cache
	if db, ok := dbCache[path]; ok {
		return db, nil
	}

	// Open new connection
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}

	// Test connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}

	// Cache it
	dbCache[path] = db
	return db, nil
}

func buildQuery(b *banquet.Banquet) (string, []interface{}) {
	// Determine table
	table := b.Table
	if table == "" {
		table = "tb0" // Default table
	}

	// Build SELECT clause
	selectClause := "*"
	if len(b.Select) > 0 && b.Select[0] != "*" {
		// Filter out table name if it appears in select list
		var columns []string
		for _, col := range b.Select {
			// Skip if column name matches table name (banquet parser bug)
			if col != table {
				columns = append(columns, col)
			}
		}

		// Only use columns if we have any after filtering
		if len(columns) > 0 {
			selectClause = ""
			for i, col := range columns {
				if i > 0 {
					selectClause += ", "
				}
				selectClause += col
			}
		}
	}

	query := fmt.Sprintf("SELECT %s FROM %s", selectClause, table)

	// WHERE clause
	var args []interface{}
	if b.Where != "" {
		query += " WHERE " + b.Where
	}

	// ORDER BY clause
	if b.OrderBy != "" {
		query += " ORDER BY " + b.OrderBy
		if b.SortDirection != "" {
			query += " " + b.SortDirection
		}
	}

	// GROUP BY clause
	if b.GroupBy != "" {
		query += " GROUP BY " + b.GroupBy
	}

	// HAVING clause
	if b.Having != "" {
		query += " HAVING " + b.Having
	}

	// LIMIT clause
	if b.Limit != "" {
		query += " LIMIT " + b.Limit
	}

	// OFFSET clause
	if b.Offset != "" {
		query += " OFFSET " + b.Offset
	}

	return query, args
}

func sendError(w http.ResponseWriter, message string) {
	log.Printf("Error: %s", message)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)
	json.NewEncoder(w).Encode(QueryResponse{Error: message})
}
