import Foundation
import TasksCore

/// `swift run golden [outdir]`: writes the golden JSON files the TypeScript port is tested against (README.md).
@main
struct Golden {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "../test/golden", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        func write(_ name: String, _ value: J, cases: Int) throws {
            let text = JSONOut.render(value)
            try Data(text.utf8).write(to: outDir.appendingPathComponent(name))
            print("\(name): \(cases) cases, \(text.utf8.count) bytes")
        }

        let fold = try CoreFold.build()
        try write("core-fold.json", fold.fold, cases: fold.foldCount)
        try write("inverse.json", fold.inverse, cases: fold.inverseCount)
        let (opJSON, opCount) = OpJSONCases.build(fromLogs: fold.opTexts)
        try write("op-json.json", opJSON, cases: opCount)
        let day = DayCases.build()
        if case .obj(let o) = day, case .arr(let a) = o["cases"]! { try write("day.json", day, cases: a.count) }
        let (cal, calCount) = CalendarCases.build()
        try write("calendar-date.json", cal, cases: calCount)
        let (phrase, phraseCount) = PhraseCases.build()
        try write("date-phrase.json", phrase, cases: phraseCount)
        let (ordering, orderingCount) = OrderingCases.build()
        try write("ordering.json", ordering, cases: orderingCount)

        for w in warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
    }
}
