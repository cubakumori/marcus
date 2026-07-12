import AppKit
import MarcusCore

/// Flat, indented list of the document's headings; selecting one jumps the
/// editor there. Fed from the highlighter's scan — it never parses anything.
final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var onSelect: ((OutlineItem) -> Void)?

    private var items: [OutlineItem] = []
    private var tableView: NSTableView!

    override func loadView() {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.allowsEmptySelection = true
        tableView.addTableColumn(NSTableColumn(identifier: .init("title")))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        // VoiceOver names the sidebar; each row adds its heading level (below).
        tableView.setAccessibilityLabel(L("Document Outline"))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 220, height: 640)
        self.tableView = tableView
        view = scrollView
    }

    func show(_ items: [OutlineItem]) {
        guard items != self.items else { return }
        self.items = items
        tableView.reloadData()
    }

    /// Accessibility naming for `-MarcusDebugDumpA11y` — the sidebar's label
    /// and each row's spoken label ("Level 2, Title"), asserted without
    /// VoiceOver. Materializes the cells (makeIfNecessary) so the labels set
    /// in the view factory are present.
    var debugTableA11yLabel: String { tableView.accessibilityLabel() ?? "" }
    var debugRowA11yLabels: [String] {
        items.indices.map { row in
            tableView.view(atColumn: 0, row: row, makeIfNecessary: true)?.accessibilityLabel() ?? ""
        }
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onSelect?(items[row])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title)
        label.lineBreakMode = .byTruncatingTail
        label.font = item.level == 1
            ? NSFont.systemFont(ofSize: 13, weight: .semibold)
            : NSFont.systemFont(ofSize: 12)
        label.textColor = item.level <= 2 ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        // VoiceOver reads the indentation as nothing; state the level so the
        // heading hierarchy is audible ("Level 2, Section title").
        cell.setAccessibilityLabel(String(format: L("Level %@, %@"), "\(item.level)", item.title))
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: cell.leadingAnchor, constant: 8 + CGFloat(item.level - 1) * 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
