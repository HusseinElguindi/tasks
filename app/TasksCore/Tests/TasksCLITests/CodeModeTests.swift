import TasksCore
import XCTest
@testable import TasksCLI

/// Code mode (`tasks run`, `tasks mcp`) against the in-memory server, with the real Deno sandbox. Skipped when
/// Deno isn't on PATH.
@MainActor
final class CodeModeTests: CLITestCase {
    override func setUp() async throws {
        try await super.setUp()
        vars["PATH"] = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let e = env(out: { _ in }, err: { _ in })
        guard (try? CodeMode.deno(e)) != nil else { throw XCTSkip("Deno isn't on PATH (mise use -g deno).") }
    }

    func script(_ source: String, _ flags: String...) async throws -> (code: Int32, json: JSON) {
        var out: [String] = []
        let code = await CLI.run(["run", "-", "--json"] + flags, env: env(stdin: source, out: { out.append($0) }, err: { _ in }))
        return (code, try JSON.parse(out.joined()))
    }

    func testAScriptIsOneBatchAndReturnsItsResult() async throws {
        for t in ["Milk", "Bread", "Rent"] { await tasks("add", t) }
        let r = try await script("""
        const all = await tasks.find({ text: "" });
        console.log("found", all.length);
        await tasks.setWhen(all.filter((t) => t.title !== "Rent").map((t) => t.id), "fri");
        const c = await tasks.complete(all.find((t) => t.title === "Rent")!.id);
        return { titles: all.map((t) => t.title).sort(), summary: c.summary };
        """)
        XCTAssertEqual(r.code, 0, r.json.text)
        XCTAssertEqual(r.json["result"]?["titles"], .array(["Bread", "Milk", "Rent"].map(JSON.string)))
        XCTAssertEqual(r.json["result"]?["summary"]?.stringValue, "Complete \"Rent\"")
        XCTAssertEqual(r.json["logs"], .array([.string("found 3")]))
        XCTAssertEqual(r.json["synced"], .bool(true))
        let batch = try XCTUnwrap(r.json["change"]?["batch"]?.stringValue)
        let ops = server.ops.filter { $0.batch == batch }
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(Set(ops.map(\.actor)), ["agent:test"])
        XCTAssertEqual(r.json["change"]?["summary"]?.stringValue, "Complete \"Rent\"; Set When: Fri, Nov 6 (2 tasks)")

        // Reads see the script's own writes, and the run undoes as one change.
        let undo = await tasks("undo", String(batch.prefix(6)))
        XCTAssertEqual(undo.code, 0, undo.err)
        let today = try await json("find", "")
        XCTAssertEqual(today.arrayValue?.filter { $0["when"] != .null || $0["done"] == .bool(true) }.count, 0)
    }

    func testDryRunMatchesTheRealRunAndWritesNothing() async throws {
        await tasks("add", "Milk")
        let source = "await tasks.setWhen((await tasks.find({ text: \"Milk\" }))[0].id, \"tomorrow\"); return 1;"
        let before = server.ops.count
        let dry = try await script(source, "--dry-run")
        XCTAssertEqual(dry.code, 0)
        XCTAssertEqual(dry.json["dryRun"], .bool(true))
        XCTAssertEqual(server.ops.count, before)
        let real = try await script(source)
        XCTAssertEqual(real.json["change"]?["summary"], dry.json["change"]?["summary"])
        XCTAssertEqual(real.json["change"]?["tasks"]?.arrayValue?.first?["when"]?.stringValue, "2026-11-01")
        XCTAssertEqual(server.ops.count, before + 1)
    }

    func testAFailingScriptWritesNothing() async throws {
        let thrown = try await script("await tasks.add({ title: \"Half\" });\nthrow new Error(\"boom\");")
        XCTAssertEqual(thrown.code, 1)
        XCTAssertEqual(thrown.json["error"]?["message"]?.stringValue, "boom")
        XCTAssertEqual(thrown.json["error"]?["line"]?.intValue, 2)
        XCTAssertFalse(server.ops.contains { $0.set.title == "Half" })

        let api = try await script("const x = 1;\nawait tasks.add({ title: \"Half\" });\nawait tasks.setWhen(\"zzzz9999\", \"fri\");")
        XCTAssertEqual(api.json["error"]?["type"]?.stringValue, "NotFound")
        XCTAssertEqual(api.json["error"]?["line"]?.intValue, 3, "the script's line, not the bridge's")
        XCTAssertFalse(server.ops.contains { $0.set.title == "Half" })

        let typo = try await script("await tasks.compelte(\"x\");")
        XCTAssertTrue(typo.json["error"]?["message"]?.stringValue?.contains("did you mean complete?") == true, typo.json.text)

        let wrongType = try await script("await tasks.rename(\"abcd\", 5);")
        XCTAssertEqual(wrongType.json["error"]?["type"]?.stringValue, "Invalid")

        let syntax = try await script("let x: number = ;")
        XCTAssertEqual(syntax.json["error"]?["type"]?.stringValue, "SyntaxError")
    }

    func testLimits() async throws {
        vars["TASKS_RUN_TIMEOUT"] = "1"
        let spin = try await script("while (true) {}")
        XCTAssertEqual(spin.code, 1)
        XCTAssertEqual(spin.json["error"]?["type"]?.stringValue, "Limit")
        vars["TASKS_RUN_TIMEOUT"] = nil

        let big = try await script("return \"x\".repeat(200000);")
        XCTAssertEqual(big.json["error"]?["type"]?.stringValue, "Limit")

        let many = try await script("for (let i = 0; i < 501; i++) await tasks.add({ title: `t${i}` });")
        XCTAssertEqual(many.json["error"]?["type"]?.stringValue, "Limit")
        XCTAssertFalse(server.ops.contains { $0.set.title == "t0" })

        let logs = try await script("for (let i = 0; i < 250; i++) console.log(i);")
        XCTAssertEqual(logs.json["logs"]?.arrayValue?.count, 201)
    }

    /// The child can't read or write files, read env, use the network, spawn processes, load native code, or
    /// import remote modules (the default allow-list closed by --no-remote --deny-import).
    func testTheSandboxDeniesEverythingButTasks() async throws {
        let r = try await script("""
        const out: Record<string, string> = {};
        const probe = async (k: string, f: () => unknown) => { try { await f(); out[k] = "ALLOWED"; } catch (e) { out[k] = String(e); } };
        await probe("read", () => Deno.readTextFileSync("/etc/hosts"));
        await probe("write", () => Deno.writeTextFileSync("x.txt", "x"));
        await probe("env", () => Deno.env.get("HOME"));
        await probe("net", () => fetch("http://127.0.0.1:2/"));
        await probe("run", () => new Deno.Command("/bin/ls").outputSync());
        await probe("ffi", () => Deno.dlopen("/usr/lib/libSystem.dylib", {}));
        await probe("import", () => import("https://esm.sh/left-pad"));
        return out;
        """)
        let out = try XCTUnwrap(r.json["result"])
        for k in ["read", "write", "env", "net", "run", "ffi"] {
            XCTAssertTrue(out[k]?.stringValue?.contains("NotCapable") == true, "\(k): \(out[k]?.text ?? "nil")")
        }
        XCTAssertTrue(out["import"]?.stringValue?.contains("--no-remote") == true, out["import"]?.text ?? "")
    }

    func testMCP() async throws {
        let e = env(out: { _ in }, err: { _ in })
        let o = Options()
        let initialize = await MCP.handle(try JSON.parse(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#), env: e, options: o)
        XCTAssertEqual(initialize?["result"]?["serverInfo"]?["name"]?.stringValue, "tasks")
        let note = await MCP.handle(try JSON.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), env: e, options: o)
        XCTAssertNil(note)
        let list = await MCP.handle(try JSON.parse(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#), env: e, options: o)
        XCTAssertEqual(list?["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue }, ["tasks_types", "tasks_run"])
        let types = await MCP.handle(try JSON.parse(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tasks_types","arguments":{}}}"#), env: e, options: o)
        XCTAssertEqual(types?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue, TypeScript.declarations())
        let run = await MCP.handle(try JSON.parse(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"tasks_run","arguments":{"script":"return (await tasks.add({ title: \"From MCP\" })).title;"}}}"#), env: e, options: o)
        let text = try XCTUnwrap(run?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertEqual(try JSON.parse(text)["result"]?.stringValue, "From MCP")
        XCTAssertEqual(run?["result"]?["isError"], .bool(false))
        XCTAssertTrue(server.ops.contains { $0.set.title == "From MCP" })
    }

    /// Headings and a list's notes (§23): addHeading and setListNotes; a heading in complete() throws and the run
    /// writes nothing.
    func testHeadingsAndListNotes() async throws {
        await tasks("list", "add", "PHYS 122")
        for t in ["Lab 1", "Midterm"] { await tasks("add", t, "--list", "PHYS 122") }
        let r = try await script("""
        const lab = (await tasks.find({ text: "Lab 1" }))[0];
        const h = await tasks.addHeading({ name: "Labs", list: "PHYS 122", place: { before: lab.id } });
        await tasks.setListNotes("PHYS 122", "Lectures **MWF**");
        const l = await tasks.list("PHYS 122");
        return { kind: h.kind, rows: l.open.map((t) => (t.kind ? "# " : "") + t.title), notes: l.list.notes, open: l.list.open };
        """)
        XCTAssertEqual(r.code, 0, r.json.text)
        XCTAssertEqual(r.json["result"]?["kind"]?.stringValue, "heading")
        XCTAssertEqual(r.json["result"]?["rows"], .array(["# Labs", "Lab 1", "Midterm"].map(JSON.string)))
        XCTAssertEqual(r.json["result"]?["notes"]?.stringValue, "Lectures **MWF**")
        XCTAssertEqual(r.json["result"]?["open"]?.intValue, 2)

        let before = server.ops.count
        let failed = try await script("""
        const l = await tasks.list("PHYS 122");
        await tasks.rename(l.open[1].id, "Lab one");
        await tasks.complete(l.open.map((t) => t.id));
        """)
        XCTAssertEqual(failed.code, 1)
        XCTAssertEqual(failed.json["error"]?["type"]?.stringValue, "Invalid")
        XCTAssertTrue(failed.json["error"]?["message"]?.stringValue?.contains("Labs is a heading") == true, failed.json.text)
        XCTAssertEqual(server.ops.count, before, "a run that throws writes nothing")
    }

    /// tasks.d.ts is generated from the table; this golden copy makes any change show up in review.
    /// `TASKS_WRITE_GOLDEN=1 swift test --filter testDeclarationsGolden` rewrites it.
    func testDeclarationsGolden() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("tasks.d.ts")
        let generated = TypeScript.declarations()
        if ProcessInfo.processInfo.environment["TASKS_WRITE_GOLDEN"] == "1" {
            try generated.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), generated)
        for c in Commands.methods { XCTAssertTrue(generated.contains("  \(c.method!)("), c.method!) }
    }

    /// docs/AGENTS.md names every command.
    func testAgentsGuideCoversEveryCommand() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/AGENTS.md")
        let guide = try String(contentsOf: url, encoding: .utf8)
        for c in Commands.all { XCTAssertTrue(guide.contains("tasks \(c.name)"), "docs/AGENTS.md doesn't mention tasks \(c.name)") }
        for c in Commands.methods { XCTAssertTrue(guide.contains("\(c.method!)("), "docs/AGENTS.md doesn't mention \(c.method!)(") }
    }
}
