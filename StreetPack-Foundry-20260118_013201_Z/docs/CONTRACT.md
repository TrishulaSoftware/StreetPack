# Street Pack CLI Contract (v0.1)

## Required flags (every tool)
- `--help` / `-h`
- `--version`
- `--json` (emit machine-readable output)
- `--out <path>` (write report/output to file)
- `--receipt-dir <dir>` (override receipt directory)

## Recommended flags (mutating tools)
- `--dry-run` (do not mutate; report what would happen)

## Receipts
Tools SHOULD write a JSON receipt for each run under:
`~/.local/share/streetpack/receipts/<tool>/`

Receipt fields (baseline):
- tool, version
- utc, host, user, cwd
- argv (sanitized)
- elapsed_ms
- result (ok|findings|error)
- summary (counts)
- out_path (if used)

Street Pack doctrine:
- safe-by-default, dry-run-first, receipts/evidence-friendly
