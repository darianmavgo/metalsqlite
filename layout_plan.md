# Layout Plan: Compacting Columns (e.g., is_dir)

The goal is to reduce the width of the `is_dir` column (and similar small-data columns) to 1/3 of their current size while keeping other columns readable.

## Status Quo
- Columns currently have a min-width of 1% of window width.
- Columns measure content width from the first batch and add 20pt padding.
- `is_dir` is often oversized because it inherits the same padding and min-width logic as larger text columns.

## Proposed Strategy

### 1. Column-Specific Heuristics
- Implement a detection mechanism for "compact" columns. If a column name is `is_dir`, `id`, or consists only of very short numeric values (0/1), reduce its padding.
- For `is_dir`, specifically set a maximum initial width that is significantly smaller than text columns.

### 2. Reduced Padding for Numeric Columns
- Instead of a global `+ 20` padding, use dynamic padding based on column content type.
- Numeric columns (like `is_dir`) will use `+ 6` padding.

### 3. Text Compression / Font Sizing
- For the `is_dir` column specifically, we can use a slightly smaller font or center-align the content to make the compaction look intentional.

### 4. Implementation Details
- In `calculateAndSetColumnWidths`, add a check:
  ```swift
  let isCompact = column.title.lowercased().contains("is_dir") || column.title.lowercased() == "id"
  let padding: CGFloat = isCompact ? 6 : 20
  let columnMin: CGFloat = isCompact ? (minColumnWidth / 3) : minColumnWidth
  ```

## Expected Result
- `is_dir` will shrink from its current size (which likely includes significant empty space) to a tightly fitted width representing roughly 1/3 of the previous footprint.
