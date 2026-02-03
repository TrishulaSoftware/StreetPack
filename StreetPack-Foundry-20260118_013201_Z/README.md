# Street Pack Foundry

Generated: 20260118_013201_Z

This is a **repo-per-tool** scaffolding pack for Street Pack CLI utilities.

## Quick start
1) Run smoke tests:
```bash
./bootstrap/smoke_all.sh
```

2) Install all tools to ~/.local/bin:
```bash
./install_all.sh
```

3) Test drive (safe commands):
```bash
dirscope --root .
secretsniff --root .
hashscan --root . --manifest /tmp/hashscan.manifest
diffwatch --root . --state /tmp/diffwatch.state
```

4) Uninstall all:
```bash
./uninstall_all.sh
```
