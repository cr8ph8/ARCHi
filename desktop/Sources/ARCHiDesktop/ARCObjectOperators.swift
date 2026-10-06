import Foundation

/// Bounded native adaptation of pythonProjects' connected_components, object crops
/// and keep_component_rank. Components use four-neighbor, same-color connectivity;
/// zero is background. Selection does not need the donor's hole/topology features.
/// The caller charges its bounded cell budget before invoking an operator.
enum ARCObjectOperators {
    enum Operation: String, CaseIterable, Sendable {
        case cropLargest, cropSmallest, keepLargest, keepSmallest
    }

    static func apply(
        _ operation: Operation,
        to grid: ARCGrid,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> ARCGrid? {
        try checkCancellation(isCancelled)
        guard (1...30).contains(grid.count), let width = grid.first?.count,
              (1...30).contains(width) else {
            throw ARCSolverError.invalidInput("ARC grids must have 1–30 rows and columns.")
        }
        for row in grid {
            try checkCancellation(isCancelled)
            guard row.count == width else {
                throw ARCSolverError.invalidInput("ARC grids must be rectangular.")
            }
            for cell in row {
                try checkCancellation(isCancelled)
                guard (0...9).contains(cell) else {
                    throw ARCSolverError.invalidInput("ARC cells must be integers from 0 through 9.")
                }
            }
        }

        let height = grid.count
        var seen = Array(repeating: Array(repeating: false, count: width), count: height)
        var components: [Component] = []
        for row in 0..<height {
            for column in 0..<width {
                try checkCancellation(isCancelled)
                let color = grid[row][column]
                guard color != 0, !seen[row][column] else { continue }
                var cells = [Cell(row: row, column: column)]
                seen[row][column] = true
                var head = 0
                var minRow = row, maxRow = row, minColumn = column, maxColumn = column
                while head < cells.count {
                    try checkCancellation(isCancelled)
                    let cell = cells[head]
                    head += 1
                    minRow = min(minRow, cell.row)
                    maxRow = max(maxRow, cell.row)
                    minColumn = min(minColumn, cell.column)
                    maxColumn = max(maxColumn, cell.column)
                    for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        try checkCancellation(isCancelled)
                        let nextRow = cell.row + dr, nextColumn = cell.column + dc
                        guard nextRow >= 0, nextRow < height, nextColumn >= 0, nextColumn < width,
                              !seen[nextRow][nextColumn], grid[nextRow][nextColumn] == color else { continue }
                        seen[nextRow][nextColumn] = true
                        cells.append(Cell(row: nextRow, column: nextColumn))
                    }
                }
                components.append(Component(color: color, cells: cells,
                    minRow: minRow, maxRow: maxRow, minColumn: minColumn, maxColumn: maxColumn,
                    discoveryIndex: components.count))
            }
        }
        // Only the donor order's first/last component is needed, so select in one
        // pass instead of sorting. Discovery order preserves Python's stable ties.
        let chooseLargest = operation == .cropLargest || operation == .keepLargest
        var selected: Component?
        for candidate in components {
            try checkCancellation(isCancelled)
            guard let current = selected else {
                selected = candidate
                continue
            }
            if chooseLargest ? precedes(candidate, current) : precedes(current, candidate) {
                selected = candidate
            }
        }
        try checkCancellation(isCancelled)
        guard let component = selected else { return nil }

        switch operation {
        case .cropLargest, .cropSmallest:
            var output: ARCGrid = []
            for row in component.minRow...component.maxRow {
                try checkCancellation(isCancelled)
                // Cropping keeps other components inside the selected bounding box.
                output.append(Array(grid[row][component.minColumn...component.maxColumn]))
            }
            try checkCancellation(isCancelled)
            return output
        case .keepLargest, .keepSmallest:
            var output = Array(repeating: Array(repeating: 0, count: width), count: height)
            for cell in component.cells {
                try checkCancellation(isCancelled)
                output[cell.row][cell.column] = component.color
            }
            try checkCancellation(isCancelled)
            return output
        }
    }

    private struct Cell {
        let row: Int
        let column: Int
    }

    private struct Component {
        let color: Int
        let cells: [Cell]
        let minRow: Int
        let maxRow: Int
        let minColumn: Int
        let maxColumn: Int
        let discoveryIndex: Int
    }

    /// Donor key: (-area, color, minRow, maxRow, minColumn, maxColumn).
    private static func precedes(_ lhs: Component, _ rhs: Component) -> Bool {
        if lhs.cells.count != rhs.cells.count { return lhs.cells.count > rhs.cells.count }
        if lhs.color != rhs.color { return lhs.color < rhs.color }
        if lhs.minRow != rhs.minRow { return lhs.minRow < rhs.minRow }
        if lhs.maxRow != rhs.maxRow { return lhs.maxRow < rhs.maxRow }
        if lhs.minColumn != rhs.minColumn { return lhs.minColumn < rhs.minColumn }
        if lhs.maxColumn != rhs.maxColumn { return lhs.maxColumn < rhs.maxColumn }
        return lhs.discoveryIndex < rhs.discoveryIndex
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task<Never, Never>.isCancelled { throw CancellationError() }
    }
}
