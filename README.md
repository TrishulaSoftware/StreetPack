# StreetPack

[![Python package (CI)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/python-package.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/python-package.yml)
[![Pylint (soft)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/pylint.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/pylint.yml)
[![CodeQL](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/codeql.yml)

StreetPack ships with three always-on workflows that run on every push and pull request:

- **Python package (CI)** — runs a Python matrix (**3.10 / 3.11 / 3.12**), installs dependencies when present, and executes tests (smoke test included).
- **Pylint (soft)** — runs lint checks in non-blocking mode (signals issues early without breaking builds while the project evolves).
- **CodeQL** — performs static security analysis and reports findings under GitHub **Security → Code scanning alerts**.


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

