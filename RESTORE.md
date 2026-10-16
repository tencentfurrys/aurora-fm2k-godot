# Restoring this backup (aurora-fm2k-godot)

This is a full backup of the Fighting is Magic: Aurora (FM2K) reverse-engineering
workspace, taken on Windows (`C:\Users\RDP\Documents\Default Project`).

## What's here
- `aurora_fm2k/`         - extracted/parsed game data: .player/.kgt/.stage/.demo
                           binaries, ~62k sprite BMPs, 2k sounds, parsed JSON dumps
- `aurora_fm2k/Aurora.json`, `Title.json`, `Title.demo` - stored via **Git LFS**
- `godot/`               - the Godot 4.3 bridge project (v0.4 milestone, tests pass)
- `tools/`               - fm2k_compile.py + RE helpers
- `fm2ndparser-source/`  - parser source used to dig the binaries
- `ref_dark_chocolate/`  - stock FM2K reference build for byte-level checks

## Restore on a new machine
```powershell
git lfs install                      # BEFORE the clone (https://git-lfs.com)
git clone https://github.com/tencentfurrys/aurora-fm2k-godot.git
cd aurora-fm2k-godot
```
The LFS files fetch automatically during a normal clone (needs the repo's
~500 MB LFS quota untouched).

## Verify after clone
- `git lfs ls-files`           -> 3 tracked files, all pointers resolved
- `python tools/fm2k_compile.py "Applejack" "Rainbow Dash" --stage "Training Stage" --no-kgt`
- godot: run `--headless --path godot res://test/input_test.tscn` -> INPUT-TEST-PASS
   (run `--headless --import` once after adding new class_name scripts)
