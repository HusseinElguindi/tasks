import Foundation

extension Markdown.Document {
    /// An ordered item's shown number, by line index: lists number themselves from their first item (dc:2293), so
    /// "1. 1. 1." shows 1, 2, 3. A run is the list items one after another; each level counts on its own, and a bullet
    /// or a checklist item at a level ends that level's count. Moved verbatim from the Mac app's `NotesDocument.update`
    /// (app/Tasks/Detail/NotesMarkdown.swift), so every client numbers the same way.
    public var shownNumbers: [Int: Int] {
        var numbers: [Int: Int] = [:]
        var run: [Int?] = []
        for l in lines {
            guard l.isListItem else { run = []; continue }
            if run.count > l.level + 1 { run.removeLast(run.count - l.level - 1) }
            while run.count <= l.level { run.append(nil) }
            if l.kind == .ordered {
                let n = run[l.level] ?? l.number
                numbers[l.index] = n
                run[l.level] = n + 1
            } else {
                run[l.level] = nil
            }
        }
        return numbers
    }
}
