import Foundation
import TasksCore

/// Code mode, `tasks run` (docs/SDK-PLAN.md §6). The script runs in a Deno child with no permissions, an empty
/// environment and an empty working directory; its only capability is `tasks`, whose calls come back here over
/// stdio and run on this command's fork. The whole script is one change, committed once it returns.
@MainActor
enum CodeMode {
    /// The JS side, written to the run's temp directory. Never `deno eval`: it takes no permission flags.
    static let bridge = #"""
    // tasks run bridge: `tasks` calls go to the host over stdout; replies come back on stdin, one JSON per line.
    const enc = new TextEncoder();
    function send(o) {
      const bytes = enc.encode(JSON.stringify(o) + "\n");
      let n = 0;
      while (n < bytes.length) n += Deno.stdout.writeSync(bytes.subarray(n));
    }
    async function* lines(stream) {
      let buf = "";
      for await (const chunk of stream.pipeThrough(new TextDecoderStream())) {
        buf += chunk;
        let i;
        while ((i = buf.indexOf("\n")) >= 0) { yield buf.slice(0, i); buf = buf.slice(i + 1); }
      }
    }
    const input = lines(Deno.stdin.readable);
    const source = JSON.parse((await input.next()).value);
    const waiting = new Map();
    let next = 0;
    (async () => {
      for await (const line of input) {
        const m = JSON.parse(line);
        const w = waiting.get(m.id);
        waiting.delete(m.id);
        if (m.error) {
          const e = new Error(m.error.message);
          e.name = m.error.type;
          Object.assign(e, m.error, { site: w.site });
          w.reject(e);
        } else w.resolve(m.result);
      }
    })();
    // The call site's stack, taken now: an error that comes back later only has the bridge's frames.
    const call = (method, args) => new Promise((resolve, reject) => {
      const id = ++next;
      waiting.set(id, { resolve, reject, site: new Error().stack });
      send({ call: id, method, args: args.map((a) => (a === undefined ? null : a)) });
    });
    globalThis.tasks = new Proxy({}, {
      get: (_, name) => (typeof name !== "string" || name === "then" ? undefined : (...args) => call(name, args)),
    });
    const show = (v) => (typeof v === "string" ? v : (() => { try { return JSON.stringify(v); } catch { return String(v); } })());
    for (const k of ["log", "info", "warn", "error", "debug"]) console[k] = (...a) => send({ log: a.map(show).join(" ") });
    const where = (e) => {
      const m = /data:[^\s)]*?:(\d+):(\d+)/.exec(String(e && e.site) + " " + String(e && e.stack) + " " + String(e && e.message));
      return m ? { line: Number(m[1]) - 1, column: Number(m[2]) } : {};
    };
    const clean = (s) => String(s).replace(/data:application\/typescript;base64,[A-Za-z0-9+\/=]+/g, "script");
    try {
      let bin = "";
      for (const b of enc.encode(source)) bin += String.fromCharCode(b);
      const url = "data:application/typescript;base64," + btoa(bin);
      const mod = await import(url);
      const result = await mod.default();
      send({ done: true, result: result === undefined ? null : JSON.parse(JSON.stringify(result) ?? "null") });
    } catch (e) {
      const known = e && typeof e === "object" && "type" in e && "message" in e;
      send({ done: true, error: known
        ? { type: e.type, message: e.message, field: e.field ?? null, candidates: e.candidates ?? [], ...where(e) }
        : { type: /^SyntaxError:|could not be parsed/.test(String(e && e.message)) ? "SyntaxError" : (e && e.name) || "Error",
            message: clean((e && e.message) ?? e).replace(/^SyntaxError: /, ""), ...where(e) } });
    }
    Deno.exit(0);
    """#

    static var timeout: Double { 10 }
    static let maxResultBytes = 100_000
    static let maxLogLines = 200

    struct Outcome {
        var ok: Bool
        var result: JSON = .null
        var error: JSON = .null
        var logs: [String] = []
    }

    /// `tasks run [file|-]`: reads the script, runs it, and commits its change unless it's a dry run.
    static func run(_ c: Context, file: String?) async throws -> Reply {
        let source: String
        if let file, file != "-" {
            guard let s = try? String(contentsOfFile: (file as NSString).expandingTildeInPath, encoding: .utf8) else {
                throw CLIError.invalid("Can't read \(file).", field: "file")
            }
            source = s
        } else {
            source = c.env.readStdin()
        }
        let (json, failed) = try await execute(source, c, dryRun: c.options.dryRun)
        if failed { c.exitCode = 1 } else if json["synced"] == .bool(false) { c.exitCode = 75 }
        return .value(json, text(json))
    }

    /// Runs one script on `c`'s fork and returns the result object (§6), committing unless `dryRun`.
    static func execute(_ source: String, _ c: Context, dryRun: Bool) async throws -> (JSON, failed: Bool) {
        let outcome = try await sandbox(source, c)
        var logs = outcome.logs
        if logs.count > maxLogLines { logs = Array(logs.prefix(maxLogLines)) + ["… \(outcome.logs.count - maxLogLines) more lines dropped"] }
        func failure(_ error: JSON) -> (JSON, Bool) {
            (JSON(["ok": .bool(false), "error": error, "logs": .array(logs.map(JSON.string)), "change": .null]), true)
        }
        guard outcome.ok else { return failure(outcome.error) }
        let size = outcome.result.text.utf8.count
        if size > maxResultBytes {
            return failure(JSON(["type": .string("Limit"), "message": .string("The result is \(size / 1000) KB; the limit is 100 KB. Return less (ids, counts).")]))
        }
        if c.ops.count > 500 && !c.options.large {
            return failure(JSON(["type": .string("Limit"), "message": .string("The script made \(c.ops.count) ops; one change is at most 500 (pass --large to split it).")]))
        }
        let change = c.ops.isEmpty ? JSON.null : try c.changeJSON()
        if dryRun {
            let p = try c.p
            let diff = try c.describe(p).diff(c.changes(), refs: Render(p))
            return (JSON(["ok": .bool(true), "result": outcome.result, "logs": .array(logs.map(JSON.string)), "change": change,
                          "dryRun": .bool(true), "diff": .array(diff.map(JSON.string))]), false)
        }
        let synced = try await c.commit()
        return (JSON(["ok": .bool(true), "result": outcome.result, "logs": .array(logs.map(JSON.string)), "change": change,
                      "synced": .bool(synced)]), false)
    }

    static func text(_ j: JSON) -> [String] {
        var out = (j["logs"]?.arrayValue ?? []).compactMap(\.stringValue)
        if j["ok"] == .bool(false), let e = j["error"] {
            let at = e["line"]?.intValue.map { " (line \($0))" } ?? ""
            out.append("error: \(e["type"]?.stringValue ?? "Error")\(at): \(e["message"]?.stringValue ?? "")")
            out.append("Nothing was written.")
            return out
        }
        if let r = j["result"], r != .null { out.append("result: " + r.text) }
        for d in j["diff"]?.arrayValue ?? [] { if let s = d.stringValue { out.append(s) } }
        if let change = j["change"], let summary = change["summary"]?.stringValue {
            if j["dryRun"] == .bool(true) {
                out.append("Dry run: \(summary). Nothing was written.")
            } else if let b = change["batch"]?.stringValue {
                out.append("\(summary) · undo: tasks undo \(b.prefix(6))")
            }
        }
        return out
    }

    // MARK: The sandbox

    static func deno(_ env: Environment) throws -> String {
        if let d = env["TASKS_DENO"] { return d }
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let path = "\(dir)/deno"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw CLIError(kind: .config, message: "tasks run needs Deno: mise use -g deno")
    }

    static func sandbox(_ source: String, _ c: Context) async throws -> Outcome {
        let deno = try deno(c.env)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        try bridge.write(to: dir.appendingPathComponent("bridge.js"), atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: deno)
        p.arguments = ["run", "--no-prompt", "--no-remote", "--deny-import", "--no-config", "--no-lock",
                       "--v8-flags=--max-old-space-size=128", "bridge.js"]
        p.environment = [:]
        p.currentDirectoryURL = dir
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        do { try p.run() } catch {
            throw CLIError(kind: .config, message: "Couldn't start Deno at \(deno): \(error.localizedDescription)")
        }
        let toChild = input.fileHandleForWriting
        func reply(_ j: JSON) { try? toChild.write(contentsOf: Data((j.text + "\n").utf8)) }
        reply(.string("export default async () => {\n" + source + "\n};\n"))

        let limit = c.env["TASKS_RUN_TIMEOUT"].flatMap(Double.init) ?? timeout
        let pid = p.processIdentifier
        let timer = Task {
            try? await Task.sleep(for: .seconds(limit))
            if !Task.isCancelled { kill(pid, SIGKILL) }
        }
        defer { timer.cancel() }

        var outcome: Outcome?
        var logs: [String] = []
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                guard let m = try? JSON.parse(line) else { continue }
                if let text = m["log"]?.stringValue {
                    logs.append(text)
                } else if let id = m["call"] {
                    reply(await answer(m["method"]?.stringValue ?? "", m["args"]?.arrayValue ?? [], id: id, c))
                } else if m["done"] != nil {
                    outcome = m["error"].map { Outcome(ok: false, error: $0, logs: logs) }
                        ?? Outcome(ok: true, result: m["result"] ?? .null, logs: logs)
                    break
                }
            }
        } catch {}
        try? toChild.close()
        if p.isRunning { kill(pid, SIGKILL) }
        p.waitUntilExit()
        if let outcome { return outcome }
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().suffix(2000), as: UTF8.self)
        if p.terminationReason == .uncaughtSignal && p.terminationStatus == SIGKILL {
            return Outcome(ok: false, error: JSON(["type": .string("Limit"), "message": .string("The script ran longer than \(Int(limit)) s, so it was stopped.")]), logs: logs)
        }
        let why = stderr.contains("heap") ? "it ran out of memory (128 MB)" : "Deno exited (\(p.terminationStatus)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        return Outcome(ok: false, error: JSON(["type": .string("Limit"), "message": .string("The script stopped: \(why).")]), logs: logs)
    }

    /// One `tasks.<method>(…)` call from the script, run like the CLI command with the same name in the table.
    static func answer(_ method: String, _ args: [JSON], id: JSON, _ c: Context) async -> JSON {
        do {
            guard let command = Commands.method(method) else {
                let names = Commands.methods.compactMap(\.method)
                let near = names.min { distance($0, method) < distance($1, method) }
                let hint = near.flatMap { distance($0, method) <= 3 ? "; did you mean \($0)?" : nil } ?? ""
                throw CLIError(kind: .notFound, message: "There's no tasks.\(method)\(hint) (tasks types lists them).")
            }
            let before = c.ops.count
            let reply = try await command.run(c, try decode(command, args))
            let result: JSON
            switch reply {
            case .value(let j, _): result = j
            case .change: result = try c.changeJSON(from: before)
            case .createdTask(let tid): result = Render(try c.p).task(try c.p.task(tid)!)
            case .createdList(let lid): result = Render(try c.p).list(try c.p.list(lid)!)
            case .text(let s): result = .string(s)
            }
            return JSON(["id": id, "result": result])
        } catch let e as CLIError {
            return JSON(["id": id, "error": JSON(["type": .string(e.kind == .usage ? "Invalid" : e.kind.rawValue), "message": .string(e.message),
                                                  "field": .str(e.field), "candidates": .array(e.candidates.map(JSON.string))])])
        } catch {
            return JSON(["id": id, "error": JSON(["type": .string("Error"), "message": .string("\(error)")])])
        }
    }

    /// Positional code-mode arguments → the command's named parameters, type-checked (Deno doesn't check types).
    static func decode(_ c: Command, _ args: [JSON]) throws -> Args {
        let name = "tasks.\(c.method!)"
        guard args.count <= c.signature.count else {
            throw CLIError.invalid("\(name) takes \(c.signature.count) argument\(c.signature.count == 1 ? "" : "s"); got \(args.count).")
        }
        var out: Args = [:]
        for (i, arg) in c.signature.enumerated() {
            guard i < args.count else { continue }
            let v = args[i]
            switch arg {
            case .param(let n):
                if v.isNull && c.param(n)!.type != .date { continue }
                out[n] = v
            case .object(let n, let fields):
                if v.isNull { continue }
                guard case .object(let members) = v else { throw CLIError.invalid("\(name): \(n) must be an object.", field: n) }
                for m in members {
                    guard fields.contains(m.key) else {
                        throw CLIError.invalid("\(name): \(n) has no field \(m.key) (it takes \(fields.joined(separator: ", "))).", field: m.key)
                    }
                    if m.value.isNull && c.param(m.key)!.type != .date { continue }
                    out[m.key] = m.value
                }
            }
        }
        let accepted = Set(c.signature.flatMap { arg -> [String] in
            switch arg {
            case .param(let n): [n]
            case .object(_, let fields): fields
            }
        })
        for p in c.params where accepted.contains(p.name) {
            guard let v = out[p.name] else {
                if !p.optional { throw CLIError.invalid("\(name) needs \(p.name).", field: p.name) }
                continue
            }
            let ok: Bool = switch p.type {
            case .text, .ref, .listRef: v.stringValue != nil
            case .refs: v.stringValue != nil || (v.arrayValue?.allSatisfy { $0.stringValue != nil } ?? false)
            case .date: v.stringValue != nil || v.isNull
            case .place: v.stringValue != nil || v["after"]?.stringValue != nil || v["before"]?.stringValue != nil
            case .bool: v.boolValue != nil
            case .int: v.intValue != nil
            }
            guard ok else { throw CLIError.invalid("\(name): \(p.name) must be \(p.type.ts).", field: p.name) }
        }
        return out
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}
