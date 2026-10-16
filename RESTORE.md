# Restoring this backup (aurora-fm2k-godot)

Full backup of the Fighting is Magic: Aurora (FM2K) reverse-engineering workspace
(~6.7 GB, ~66k files), taken 2026-10-16 from a temporary Windows machine.

## Layout: content is spread across one ref per data batch
The full file tree is not assembled as one checkout; each batch lives in its own
branch ref (disjoint paths, so they union cleanly):

| ref    | content                                                                  |
|--------|--------------------------------------------------------------------------|
| main   | sprites half B + this doc (tree = part-9 tree + RESTORE.md)              |
| part-1 | tools/, fm2ndparser-source/, root meta (png proofs, .gitattributes)      |
| part-2 | godot/  (Godot 4.3 bridge v0.4 + tests)                                 |
| part-3 | ref_dark_chocolate/  (stock FM2K reference build)                        |
| part-4 | aurora program data (.player/.kgt/log)                                   |
| part-5 | aurora stage + demo data                                                 |
| part-6 | aurora extracted audio (wav)                                             |
| part-7 | aurora parsed JSON dumps (Title.json / Aurora.json / Title.demo via LFS) |
| part-8 | aurora sprites, first half  (~31k BMPs)                                  |
| part-9 | aurora sprites, second half (~31k BMPs)                                  |

## Restore on a new machine
    git lfs install      # BEFORE cloning (https://git-lfs.com)
    git clone https://github.com/tencentfurrys/aurora-fm2k-godot.git
    cd aurora-fm2k-godot

Union-checkout every batch (order does not matter; paths are disjoint):
    cmd /c "for /L %i in (1,1,9) do git checkout part-%i -- ."

The three LFS big files arrive automatically during the clone (requires the
repo's ~500 MB LFS quota untouched).

Verify after restore:
    git lfs ls-files                  -> 3 tracked files, pointers resolved
    python tools/fm2k_compile.py "Applejack" "Rainbow Dash" --stage "Training Stage" --no-kgt
    godot: --headless --path godot res://test/input_test.tscn -> INPUT-TEST-PASS
          (run --headless --import once after adding new class_name scripts)
