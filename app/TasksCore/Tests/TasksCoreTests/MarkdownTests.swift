import XCTest
@testable import TasksCore

/// The notes' Markdown scanner against the prototype's rules (design/prototype-markdown/Main.dc.html dc:509–575).
final class MarkdownTests: XCTestCase {
    private func kinds(_ s: String) -> [Markdown.Kind] { Markdown.parse(s).lines.map(\.kind) }

    private func tokens(_ s: String) -> [(Markdown.Token.Kind, String, Int)] {
        let u = Array(s.utf16)
        return Markdown.inline(s).map { t in (t.kind, String(utf16CodeUnits: Array(u[t.inner]), count: t.inner.count), t.depth) }
    }

    private func assertTokens(_ s: String, _ want: [(Markdown.Token.Kind, String, Int)], file: StaticString = #filePath, line: UInt = #line) {
        let got = tokens(s)
        XCTAssertEqual(got.map { "\($0.0) \($0.1) \($0.2)" }, want.map { "\($0.0) \($0.1) \($0.2)" }, s, file: file, line: line)
    }

    func testLineKinds() {
        XCTAssertEqual(kinds("# A\n## B\n###### C\n####### D\n#E"), [.heading1, .heading2, .heading2, .paragraph, .paragraph])
        XCTAssertEqual(kinds("- a\n* b\n+ c\n-d\n- "), [.bullet, .bullet, .bullet, .paragraph, .bullet])
        XCTAssertEqual(kinds("1. a\n2) b\n123456789. c\n1234567890. d\n1.d"), [.ordered, .ordered, .ordered, .paragraph, .paragraph])
        XCTAssertEqual(kinds("- [ ] a\n- [x] b\n- [X]\n- [ ]b\n- [y] c"), [.task, .task, .task, .bullet, .bullet])
        XCTAssertEqual(kinds("> q\n>q\n >q"), [.quote, .quote, .paragraph])
        XCTAssertEqual(kinds("\n  \t\na"), [.blank, .blank, .paragraph])
    }

    func testListFields() {
        let d = Markdown.parse("    - [x] deep\n  3) mid")
        let a = d.lines[0], b = d.lines[1]
        XCTAssertEqual(a.kind, .task)
        XCTAssertEqual(a.level, 2)
        XCTAssertTrue(a.checked)
        XCTAssertEqual(a.box, 7)
        XCTAssertEqual(a.prefix, 10)
        XCTAssertEqual(b.kind, .ordered)
        XCTAssertEqual(b.level, 1)
        XCTAssertEqual(b.number, 3)
        XCTAssertEqual(b.delimiter, 41)
        XCTAssertEqual(b.prefix, 5)
        XCTAssertEqual(Markdown.parse("# \tTitle").lines[0].prefix, 3)
        XCTAssertEqual(Markdown.parse(">\tq").lines[0].prefix, 2)
    }

    func testFences() {
        let d = Markdown.parse("a\n```swift\n- [ ] not a task\n```\n~~~\nopen")
        XCTAssertEqual(d.lines.map(\.kind), [.paragraph, .fence, .code, .fence, .fence, .code])
        XCTAssertEqual(d.blocks.count, 2)
        XCTAssertEqual(d.blocks[0].first, 1)
        XCTAssertEqual(d.blocks[0].last, 3)
        XCTAssertTrue(d.blocks[0].closed)
        XCTAssertFalse(d.blocks[1].closed)
        XCTAssertEqual(d.lines[5].block, 1)
        XCTAssertEqual(kinds("   ```\n    ```"), [.fence, .code])
    }

    func testInline() {
        assertTokens("a **b** c", [(.bold, "b", 0)])
        assertTokens("**b _i_**", [(.bold, "b _i_", 0), (.italic, "i", 1)])
        // The closer must not be followed by a word character, so the first `__` runs on to the last (as the regex does).
        assertTokens("__b__x __c__", [(.bold, "b__x __c", 0)])
        assertTokens("snake_case_name and _it_", [(.italic, "it", 0)])
        assertTokens("*a* * b * **", [(.italic, "a", 0)])
        assertTokens("`co*de*` x", [(.code, "co*de*", 0)])
        assertTokens("``", [])
        assertTokens("[text](https://a.b/c) [no] (x) [a](b c)", [(.link, "text", 0)])
        assertTokens("see https://example.com/a_b. and http://x.y)", [(.url, "https://example.com/a_b", 0), (.url, "http://x.y", 0)])
        assertTokens("https:// x", [])
        assertTokens("***x***", [(.bold, "*x", 0)])
    }

    func testLinkTarget() {
        let s = "[t](u)"
        let t = Markdown.inline(s)[0]
        XCTAssertEqual(t.range, 0..<6)
        XCTAssertEqual(t.inner, 1..<2)
        XCTAssertEqual(t.target, 4..<5)
    }

    func testPlain() {
        let s = "**Bold** and [a link](x) and `code` _it_"
        let u = Array(s.utf16)
        XCTAssertEqual(u.withUnsafeBufferPointer { Markdown.plain($0, 0, $0.count) }, "Bold and a link and code it")
    }

    func testSummary() {
        XCTAssertEqual(NotesSummary(""), NotesSummary())
        XCTAssertFalse(NotesSummary(" \n\t").hasNotes)
        let s = NotesSummary("Plan\n- [x] one\n- [ ] two\n  - [X] three\n```\n- [ ] code\n```")
        XCTAssertTrue(s.hasNotes)
        XCTAssertEqual(s.checked, 2)
        XCTAssertEqual(s.total, 3)
    }

    /// Opening a 20,000-character note scans it in one pass (design/MARKDOWN.md §9: well under 1 ms in release).
    func testScanBudget() {
        let block = "## Heading\nSome **bold** and _italic_ text with a [link](https://example.com) and `code`.\n- [ ] item one\n- [x] item two\n> a quote\n"
        var text = ""
        while (text as NSString).length < 20_000 { text += block }
        let u = Array(text.utf16.prefix(20_000))
        var times: [Double] = []
        for _ in 0..<9 {
            let start = DispatchTime.now().uptimeNanoseconds
            u.withUnsafeBufferPointer { b in
                let d = Markdown.parse(b)
                var n = 0
                for l in d.lines { n += Markdown.inline(b, l.textStart, l.end).count }
                XCTAssertGreaterThan(n, 0)
            }
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let ms = times.sorted()[4]
        print(String(format: "benchmark markdown scan 20k: %.3f ms (budget 1.0 ms)", ms))
        #if !DEBUG
        XCTAssertLessThanOrEqual(ms, 1.0)
        #endif
    }
}
