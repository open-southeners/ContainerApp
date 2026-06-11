import CoreFoundation

/// Shared sizing constants and helpers for SwiftUI `Table` views across the app.
enum TableSizing {
    /// Approximate height of one table row, including SwiftUI's default cell padding.
    static let rowHeight: CGFloat = 28
    /// Height of the table header row.
    static let headerHeight: CGFloat = 28
    /// Upper bound; past this the table keeps its height and scrolls internally.
    static let maxHeight: CGFloat = 600

    /// Height that fits exactly `rowCount` rows plus the header, capped so long
    /// lists don't push the detail pane off-screen.
    static func height(rowCount: Int) -> CGFloat {
        let contentHeight = headerHeight + CGFloat(rowCount) * rowHeight
        return min(contentHeight, maxHeight)
    }
}
