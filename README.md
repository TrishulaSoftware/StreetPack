# StreetPack

StreetPack is a small, docked launcher for a handful of local CLI utilities, with optional receipts/outputs saved under a user data home.

## What’s in this build (UI-exposed tools)

- **hashscan** — generate/verify hash manifests
- **safedel** — safe delete (trash semantics)
- **secretsniff** — scan for credential-like patterns
- **dirscope** — inspect directory structure and size

> Note: Only the tools listed above are currently exposed in the UI for this build.

## Data paths

StreetPack stores runtime data under:

- `~/.local/share/streetpack/receipts/`
- `~/.local/share/streetpack/outputs/`

## Ship prep / artifact check

A small bash utility is included to check (and optionally clean) runtime artifacts + common repo build junk:

```bash
./streetpack_shipcheck.sh check
./streetpack_shipcheck.sh clean

