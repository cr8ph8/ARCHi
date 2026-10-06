import SwiftUI

struct ARCMetricTile: View {
    let value: String
    let title: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(WorkspaceTheme.accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WorkspaceTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityIdentifier("capabilities.solver.metric.\(identifier)")
    }
}

struct ARCPanelNotice: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold)).foregroundStyle(.orange)
            Text(detail).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// ARC colors encode data. Workspace chrome remains adaptive, and numeric rows
/// remain accessible even when a dense grid cannot display individual digits.
struct ARCNativeGrid: View {
    let grid: ARCGrid
    let title: String
    let identifier: String

    private var cellSize: CGFloat {
        let dimension = max(1, max(grid.count, grid.first?.count ?? 1))
        return min(56, (240 / CGFloat(dimension)).rounded(.down))
    }

    private var displayWidth: CGFloat {
        max(128, CGFloat(grid.first?.count ?? 0) * cellSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(grid.count) rows × \(grid.first?.count ?? 0) columns")
                .font(.caption2).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(grid.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(grid[row].indices, id: \.self) { column in
                            let value = grid[row][column]
                            Rectangle().fill(color(value), style: FillStyle(antialiased: false))
                                .overlay(Rectangle().strokeBorder(Color.gray.opacity(0.45), lineWidth: 0.5))
                                .overlay {
                                    if cellSize >= 18 {
                                        Text(String(value))
                                            .font(.system(size: min(14, cellSize * 0.3), weight: .medium, design: .monospaced))
                                            .foregroundStyle([0, 1, 2, 6, 9].contains(value) ? Color.white : Color.black)
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .accessibilityRepresentation {
                        Text("\(title), row \(row + 1): \(grid[row].map(String.init).joined(separator: ", "))")
                            .accessibilityIdentifier("capabilities.solver.grid.\(identifier).row.\(row)")
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
        }
        .frame(width: displayWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capabilities.solver.grid.\(identifier)")
    }

    private func color(_ value: Int) -> Color {
        switch value {
        case 0: .black
        case 1: Color(red: 0, green: 0.45, blue: 0.85)
        case 2: Color(red: 0.9, green: 0.2, blue: 0.2)
        case 3: Color(red: 0.2, green: 0.8, blue: 0.35)
        case 4: Color(red: 1, green: 0.85, blue: 0.2)
        case 5: Color(red: 0.65, green: 0.65, blue: 0.65)
        case 6: Color(red: 0.8, green: 0.15, blue: 0.65)
        case 7: Color(red: 1, green: 0.55, blue: 0.15)
        case 8: Color(red: 0.3, green: 0.85, blue: 0.9)
        case 9: Color(red: 0.55, green: 0.15, blue: 0.2)
        default: .clear
        }
    }
}
