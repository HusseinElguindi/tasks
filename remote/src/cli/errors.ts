// The errors a command reports; `kind` is the error's type in code mode (docs/SDK-PLAN.md §6). Port of Replica.swift's CLIError.

export type ErrorKind = "Usage" | "NotFound" | "Ambiguous" | "Invalid" | "NoActiveList" | "Limit" | "Sync" | "Busy" | "Config";

export class CLIError extends Error {
  kind: ErrorKind;
  field: string | null;
  candidates: string[];

  constructor(kind: ErrorKind, message: string, field: string | null = null, candidates: string[] = []) {
    super(message);
    this.kind = kind;
    this.field = field;
    this.candidates = candidates;
  }

  static invalid(message: string, field: string | null = null) {
    return new CLIError("Invalid", message, field);
  }

  static usage(message: string) {
    return new CLIError("Usage", message);
  }
}
