# Tasks for agents

`tasks` is a command-line replica of the user's Tasks app: the same lists, Today and dates the Mac app shows,
computed by the app's own code. Every write is one change that syncs at once and that the user (or you) can undo.
There are two ways to use it:

- **Commands** (`tasks today`, `tasks when fri 3f9a2c`) for one-step things.
- **A script** (`tasks run`) for anything with a filter, a loop or more than one step: one turn, one atomic change.

`tasks help` lists every command; `tasks help <command>` shows one with an example. `docs/SDK-PLAN.md` is the design.

## Setup

- Install: `app/Scripts/install-cli.sh` (puts `tasks` in `~/.local/bin`).
- Server: `TASKS_URL`, or a `TASKS_URL=https://…` line in `~/.tasks-sync.env`. There is no default.
- Token: `TASKS_TOKEN`, else `API_TOKEN` in `~/.tasks-sync.env`. Never print it; `tasks status` says where it came
  from without showing it.
- Who you are: your changes are labelled `agent:claude-code` under Claude Code (`CLAUDECODE=1`), else `TASKS_ACTOR`,
  else `cli`. `--actor A` overrides it for one command.
- `tasks status` shows the server, the actor, the replica and anything waiting to sync.

## Reading

| Command | Shows |
|---|---|
| `tasks today` | Today: open tasks with When today or earlier, or due today or overdue, by list in sidebar order; then those completed today |
| `tasks lists` | The sidebar: active lists with their open counts |
| `tasks ls School [--done]` | One list's open tasks in order (`--done` adds the completed ones). No list means the first |
| `tasks archive` | Archived lists |
| `tasks show 3f9a2c [--history]` | Every field and the notes (Markdown); `--history` adds who changed it and when |
| `tasks find milk [--list L] [--done \| --open] [--deleted]` | Tasks whose title or notes contain the text, in any list |
| `tasks date "next fri"` | What a date phrase means today, without writing |
| `tasks log [--actor 'agent:*'] [--since 2h] [--task T]` | What changed, newest first, with who did it and the undo command |

Every read pulls first, so it's current. `--cached` reads the replica without the network.

## Writing

| Command | Does |
|---|---|
| `tasks add "Buy milk" [--list L] [--today] [--when D] [--deadline D] [--notes TEXT\|-] [--top \| --after R \| --before R] [--key K]` | A new task at the bottom of the list (no list: the first list) |
| `tasks rename 3f9a2c "Buy oat milk"` | Retitle |
| `tasks notes 3f9a2c - < notes.md` / `tasks notes 3f9a2c "- [ ] call back" --append` | Replace or extend the notes |
| `tasks done 3f9a2c 77b0e1` / `tasks undone …` / `tasks toggle …` | Complete, mark not done, or ⌘K's toggle |
| `tasks when fri 3f9a2c …` / `tasks when none …` | Set or remove When (the day it shows in Today) |
| `tasks deadline "nov 9" 3f9a2c …` / `tasks deadline none …` | Set or remove the Deadline |
| `tasks move 3f9a2c … --to School` | To another list, at the bottom, in the order given |
| `tasks move 3f9a2c --top \| --bottom \| --up \| --down \| --after R \| --before R` | Reorder (`--after`/`--before` an open task, in its list) |
| `tasks delete 3f9a2c …` / `tasks restore …` | Delete, or bring back |
| `tasks list add School [--top \| --after L]`, `tasks list rename School "School 2026"`, `tasks list move School --after Work`, `tasks list archive School`, `tasks list unarchive School` | Lists. Archiving is the app's "delete list": the tasks come back with it |
| `tasks sync` | Sync now |

- **Refs:** a task or list id, a unique id prefix of at least 4 characters (output shows 6), or a list's name.
  A ref that matches nothing or more than one thing is an error listing the candidates; nothing is guessed.
- **Dates:** `2026-11-06`, `today`, `tomorrow`, `fri`, `next week`, `3d`, `nov 9`, `the 9th`, or `none` to clear.
  They read the way the app's date field reads on Return, and every result shows the resolved date. `tasks date`
  checks one first.
- **Many at once:** pass several refs, or `-` to read them from stdin: `tasks find milk --ids | tasks done -`.
- **Safe to repeat:** everything except `toggle`; `add` too with `--key` (same key, same task).
- **Limits** fail rather than clamp: titles 1,000 characters, notes 20,000, list names 200. Moving into an archived
  list is refused.

## Output and exit codes

- Text by default, like the app's rows. `--json` prints objects (the same ones a script gets); `--ids` prints one id
  per line, for pipes. Errors go to stderr (with `--json`, as `{"error": {type, message, field, candidates}}`).
- Exit `0`: done and in the server's log. `75`: applied on this Mac but not synced yet (offline); it goes out with
  the next command that reaches the server. `1`: an error, nothing written. `2`: a usage mistake.

## Changes, review and undo

- One command (or one script) is one change, with one batch id. The output ends with how to undo it:
  `Move "Buy milk" to School · undo: tasks undo 2c1f9e`. Tell the user that line when you change their tasks.
- `--dry-run` on any write (or `tasks run --dry-run`) shows exactly what would change and writes nothing. Use it for
  anything broad, then run again without it.
- `tasks undo` undoes your newest change; `tasks undo 2c1f9e` a specific one, from anyone; `tasks redo` redoes your
  newest undo. If someone edited a field since, the undo keeps their edit and says so; `--force` overwrites it.
- `tasks log` shows every change with its actor. The app's own changes show as `app`.

## Scripts: `tasks run`

Write TypeScript against `tasks.d.ts` (`tasks types` prints it, ~1,200 tokens) and run it with `tasks run script.ts`
or `tasks run -` from stdin. Top-level `await` and `return` work; the returned value and `console.log` lines come
back. The whole script is one change: written when it returns, nothing written if it throws.

```ts
// Push everything late outside Work to tomorrow.
const { date } = await tasks.today();
const late = (await tasks.find({ done: false }))
  .filter((t) => t.listName !== "Work" && t.deadline !== null && t.deadline < date);
await tasks.setWhen(late.map((t) => t.id), "tomorrow");
return late.map((t) => t.title);
```

The API, all awaited:

- Reads: `today()`, `lists()`, `list(ref)`, `archive()`, `task(ref)`, `find({ text, list, done, deleted })`,
  `date(text)`. Reads see the script's own earlier writes.
- Tasks: `add({ title, list, notes, when, deadline, place, key })`, `rename(task, title)`, `setNotes(task, notes)`,
  `complete(tasks)`, `uncomplete(tasks)`, `toggle(tasks)`, `setWhen(tasks, date)`, `setDeadline(tasks, date)`,
  `move(tasks, { list, place })`, `delete(tasks)`, `restore(tasks)`.
- Lists: `addList(name, place)`, `renameList(list, name)`, `moveList(list, place)`, `archiveList(list)`,
  `unarchiveList(list)`.
- `undo(batch)`, as the only change in a script.

Rules:

- The script runs in Deno with no permissions: no files, network, environment or subprocesses, only `tasks`.
- Errors are typed (`NotFound`, `Ambiguous` with `candidates`, `Invalid` with `field`, `NoActiveList`, `Limit`,
  `SyntaxError`) and give the script's line.
- Limits: 10 s, 128 MB, 500 ops (`--large` for more, then not atomic), a 100 KB result, 200 log lines.
- Return ids and counts rather than whole objects when a lot changed.
- It needs Deno on PATH (`mise use -g deno`); the commands above don't.

## MCP

For a client without a shell: `claude mcp add tasks -- tasks mcp` (add `-e TASKS_ACTOR=agent:<client>` to label
its changes). `tasks mcp` serves two tools over stdio: `tasks_types` (the `tasks.d.ts` above) and `tasks_run`
(`{script, dryRun}` → the same result object as `tasks run --json`).
