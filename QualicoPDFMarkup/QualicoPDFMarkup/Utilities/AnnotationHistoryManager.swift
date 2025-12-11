//
//  AnnotationHistoryManager.swift
//  QualicoPDFMarkup
//
//  Manages annotation history for undo functionality
//

import Foundation
import PDFKit

/// Record of an annotation for undo purposes
struct AnnotationRecord {
    let annotation: PDFAnnotation
    weak var page: PDFPage?
    let timestamp: Date

    init(annotation: PDFAnnotation, page: PDFPage) {
        self.annotation = annotation
        self.page = page
        self.timestamp = Date()
    }
}

/// Manages the history stack of annotations for undo operations
@MainActor
class AnnotationHistoryManager: ObservableObject {
    /// Maximum number of undo steps to keep
    private let maxHistorySize: Int

    /// Stack of annotation records (most recent at end)
    @Published private(set) var undoStack: [AnnotationRecord] = []

    /// Whether there are annotations that can be undone
    @Published private(set) var canUndo: Bool = false

    /// Count of undoable items
    var undoCount: Int { undoStack.count }

    init(maxHistorySize: Int = 50) {
        self.maxHistorySize = maxHistorySize
    }

    /// Record a new annotation for potential undo
    func recordAnnotation(_ annotation: PDFAnnotation, on page: PDFPage) {
        let record = AnnotationRecord(annotation: annotation, page: page)
        undoStack.append(record)

        // Trim history if needed
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }

        updateCanUndo()
    }

    /// Undo the last annotation
    /// - Returns: true if an annotation was removed, false if nothing to undo
    @discardableResult
    func undo() -> Bool {
        guard let record = undoStack.popLast(),
              let page = record.page else {
            updateCanUndo()
            return false
        }

        // Remove the annotation from the page
        page.removeAnnotation(record.annotation)
        updateCanUndo()
        return true
    }

    /// Undo multiple annotations at once
    /// - Parameter count: Number of annotations to undo
    /// - Returns: Number of annotations actually removed
    @discardableResult
    func undo(count: Int) -> Int {
        var removed = 0
        for _ in 0..<count {
            if undo() {
                removed += 1
            } else {
                break
            }
        }
        return removed
    }

    /// Clear all history (e.g., when loading a new document)
    func clearHistory() {
        undoStack.removeAll()
        updateCanUndo()
    }

    /// Clear history for a specific page
    func clearHistory(for pageIndex: Int, in document: PDFDocument) {
        guard let page = document.page(at: pageIndex) else { return }

        undoStack.removeAll { record in
            record.page === page
        }
        updateCanUndo()
    }

    /// Get the type of the last annotation (for UI display)
    var lastAnnotationType: String? {
        guard let lastRecord = undoStack.last else { return nil }

        // Determine annotation type from the annotation
        if lastRecord.annotation is ImageStampAnnotation {
            return "Stamp"
        } else if lastRecord.annotation.type == PDFAnnotationSubtype.ink.rawValue {
            return "Drawing"
        } else if lastRecord.annotation.type == PDFAnnotationSubtype.highlight.rawValue {
            return "Highlight"
        } else if lastRecord.annotation.type == PDFAnnotationSubtype.freeText.rawValue {
            return "Text"
        }

        return "Annotation"
    }

    private func updateCanUndo() {
        canUndo = !undoStack.isEmpty
    }
}

// MARK: - Batch Operations

extension AnnotationHistoryManager {
    /// Record multiple annotations at once (e.g., for complex shapes)
    func recordAnnotations(_ annotations: [(PDFAnnotation, PDFPage)]) {
        for (annotation, page) in annotations {
            recordAnnotation(annotation, on: page)
        }
    }

    /// Get all annotations on a specific page from history
    func annotations(forPageIndex pageIndex: Int, in document: PDFDocument) -> [PDFAnnotation] {
        guard let page = document.page(at: pageIndex) else { return [] }

        return undoStack
            .filter { $0.page === page }
            .map { $0.annotation }
    }

    /// Undo all annotations on a specific page
    @discardableResult
    func undoAll(forPageIndex pageIndex: Int, in document: PDFDocument) -> Int {
        guard let page = document.page(at: pageIndex) else { return 0 }

        var removed = 0
        var indicesToRemove: [Int] = []

        // Find all records for this page
        for (index, record) in undoStack.enumerated() where record.page === page {
            page.removeAnnotation(record.annotation)
            indicesToRemove.append(index)
            removed += 1
        }

        // Remove from stack in reverse order to maintain indices
        for index in indicesToRemove.reversed() {
            undoStack.remove(at: index)
        }

        updateCanUndo()
        return removed
    }
}
