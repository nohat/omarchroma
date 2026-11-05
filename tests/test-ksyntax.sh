#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
export HOME=$ROOT/home XDG_DATA_HOME=$ROOT/data XDG_STATE_HOME=$ROOT/state
unset HYPRCHROMA_PALETTE_TSV
mkdir -p "$HOME"
python3 - "$REPO" <<'TEST'
import json
import os
from pathlib import Path
import subprocess
import sys
import types
repo = Path(sys.argv[1])
m = types.ModuleType("syntax")
exec(compile((repo / "lib/sync-ksyntax-theme").read_text(), "syntax", "exec"), m.__dict__)
keys = "dark_background background lighter_background foreground dark_foreground light_foreground accent selection selection_foreground red green yellow blue magenta cyan".split()
p = dict.fromkeys(keys, "#abcdef")
p.update(dark_background="#101020", accent="#ffcc00", foreground="#eeeeee", selection_foreground="#000000")
theme = m.build_theme(p)
assert theme["editor-colors"]["BackgroundColor"] == p["dark_background"]
assert theme["editor-colors"]["TextSelection"] == p["accent"]
assert len(theme["text-styles"]) == 31
print("PASS automatic selection matches KDE base and highlight roles")
for bad in ["red", "#123", "#gggggg", "#123456; touch /tmp/no"]:
    try:
        m.build_theme(dict(p, green=bad))
    except ValueError:
        continue
    raise AssertionError(bad)
print("PASS malformed palette fails before writing")
env = dict(os.environ, HYPRCHROMA_PALETTE_TSV="\n".join(f"{k}\t{v}" for k,v in p.items()))
path = Path(env["XDG_DATA_HOME"]) / "org.kde.syntax-highlighting/themes/hyprchroma.theme"
subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=env, check=True)
assert json.loads(path.read_text()) == theme
stamp = path.stat().st_mtime_ns
subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=env, check=True)
assert path.stat().st_mtime_ns == stamp
print("PASS XDG output is valid JSON and repeated sync does not rewrite it")
p["green"] = "#00ff00"
env["HYPRCHROMA_PALETTE_TSV"] = "\n".join(f"{k}\t{v}" for k,v in p.items())
subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=env, check=True)
assert json.loads(path.read_text())["text-styles"]["String"]["text-color"] == "#00ff00"
print("PASS palette changes update syntax styles")
state = types.ModuleType("state")
exec(compile((repo / "lib/hyprchroma-state").read_text().split("if __name__")[0], "state", "exec"), state.__dict__)
state_dir = Path(env["XDG_STATE_HOME"])
state.snapshot(state_dir, Path(env["XDG_DATA_HOME"]) / "hyprchroma", "qt-kde")
manifest = json.loads((state_dir / "original/manifest.json").read_text())
entry = manifest["files"]["hyprchroma_syntax"]
assert not entry["existed"]
assert "hyprchroma_syntax" in state.TARGET_FILE_KEYS["qt-kde"]
state.restore_target_captured(state_dir / "original", manifest, "qt-kde")
assert not path.exists()
print("PASS captured restore removes the generated theme through the Qt KDE lifecycle")
subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=env, check=True)
state.restore_target_stock(state_dir / "original", manifest, "qt-kde")
assert not path.exists()
print("PASS stock restore removes generated themes from XDG_DATA_HOME too")
p.update(dark_background="#eeeeee", foreground="#111111", accent="#123456")
light = m.build_theme(p)
assert light["editor-colors"]["BackgroundColor"] == "#eeeeee"
assert light["editor-colors"]["TextSelection"] == "#123456"
assert light["text-styles"]["Normal"]["text-color"] == "#111111"
print("PASS light palettes use the same automatic-selection contract")
default_env = dict(env, XDG_DATA_HOME="")
subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=default_env, check=True)
default_path = Path.home() / ".local/share/org.kde.syntax-highlighting/themes/hyprchroma.theme"
assert default_path.is_file()
saved_data_home = os.environ["XDG_DATA_HOME"]
os.environ["XDG_DATA_HOME"] = ""
try:
    assert state.syntax_theme_path() == default_path
    default_state = state_dir / "empty-xdg"
    state.snapshot(default_state, Path.home() / ".local/share/hyprchroma", "qt-kde")
    default_manifest = json.loads((default_state / "original/manifest.json").read_text())
    assert default_manifest["files"]["hyprchroma_syntax"]["path"] == str(default_path)
    state.restore_target_captured(default_state / "original", default_manifest, "qt-kde")
    assert not default_path.exists()
    subprocess.run([str(repo / "lib/sync-ksyntax-theme")], env=default_env, check=True)
    state.restore_target_stock(default_state / "original", default_manifest, "qt-kde")
    assert not default_path.exists()
finally:
    os.environ["XDG_DATA_HOME"] = saved_data_home
print("PASS empty XDG_DATA_HOME generation and both restore modes use the standard directory")
TEST
