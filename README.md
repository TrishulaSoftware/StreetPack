# StreetPack

[![Python package (CI)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/python-package.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/python-package.yml)
[![Pylint (soft)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/pylint.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/pylint.yml)
[![CodeQL](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/TrishulaSoftware/StreetPack/actions/workflows/codeql.yml)

## CI/CD (GitHub Actions)


StreetPack ships with three always-on workflows that run on every push and pull request:

- **Python package (CI)** — runs a Python matrix (**3.10 / 3.11 / 3.12**), installs dependencies when present, and executes tests (smoke test included).
- **Pylint (soft)** — runs lint checks in non-blocking mode (signals issues early without breaking builds while the project evolves).
- **CodeQL** — performs static security analysis and reports findings under GitHub **Security → Code scanning alerts**.



