#!/usr/bin/env python3
"""Build a local Quickshell-compatible qmlls VFS for Noctalia plugin development."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SHELL = Path("/etc/xdg/quickshell/noctalia-shell")
VFS_ROOT = PLUGIN_ROOT / ".qmltooling" / "vfs"
QS_ROOT = VFS_ROOT / "qs"

# Modules this plugin imports; Services is mirrored whole for nested qs.Services.* paths.
LINK_DIRS = ("Commons", "Widgets", "Services")


def shell_root() -> Path:
    env = os.environ.get("NOCTALIA_SHELL_QML", "").strip()
    if env:
        return Path(env).expanduser().resolve()
    if DEFAULT_SHELL.is_dir():
        return DEFAULT_SHELL
    raise SystemExit("Noctalia shell QML tree not found. Set NOCTALIA_SHELL_QML to your noctalia-shell path.")


def is_singleton(qml_file: Path) -> bool:
    try:
        head = qml_file.read_text(encoding="utf-8", errors="replace").splitlines()[:8]
    except OSError:
        return False
    return any("pragma Singleton" in line for line in head)


def write_qmldir(module_dir: Path, module_uri: str) -> None:
    entries: list[str] = [f"module {module_uri}"]
    for qml in sorted(p for p in module_dir.iterdir() if p.suffix == ".qml" and p.is_file()):
        if is_singleton(qml):
            entries.append(f"singleton {qml.stem} 1.0 {qml.name}")
        else:
            entries.append(f"{qml.stem} 1.0 {qml.name}")
    if len(entries) == 1:
        return
    (module_dir / "qmldir").write_text("\n".join(entries) + "\n", encoding="utf-8")


def link_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink() or dst.is_file():
        dst.unlink()
    elif dst.is_dir():
        shutil.rmtree(dst)
    dst.symlink_to(src)


def mirror_tree(src_dir: Path, dst_dir: Path) -> None:
    dst_dir.mkdir(parents=True, exist_ok=True)
    for entry in sorted(src_dir.iterdir()):
        if entry.name.startswith("."):
            continue
        target = dst_dir / entry.name
        if entry.is_dir():
            mirror_tree(entry, target)
        elif entry.is_file() and entry.suffix == ".qml":
            link_file(entry, target)


def emit_qmldirs_under(root: Path, uri_prefix: str) -> None:
    write_qmldir(root, uri_prefix)
    for child in sorted(root.iterdir()):
        if not child.is_dir() or child.name.startswith("."):
            continue
        emit_qmldirs_under(child, f"{uri_prefix}.{child.name}")


def build_vfs(shell: Path) -> Path:
    if VFS_ROOT.exists():
        shutil.rmtree(VFS_ROOT)
    QS_ROOT.mkdir(parents=True)

    for name in LINK_DIRS:
        src = shell / name
        if not src.is_dir():
            raise SystemExit(f"Missing shell module directory: {src}")
        mirror_tree(src, QS_ROOT / name)

    for name in LINK_DIRS:
        emit_qmldirs_under(QS_ROOT / name, f"qs.{name}")

    (QS_ROOT / "qmldir").write_text("module qs\n", encoding="utf-8")
    return VFS_ROOT


def write_qmlls_ini(qt_qml: Path) -> Path:
    import_paths = f".qmltooling/vfs:{qt_qml}"
    content = f'[General]\nno-cmake-calls=true\nbuildDir=".qmltooling/vfs"\nimportPaths="{import_paths}"\n'
    ini = PLUGIN_ROOT / ".qmlls.ini"
    ini.write_text(content, encoding="utf-8")
    return ini


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", type=Path, default=None, help="Path to noctalia-shell QML root")
    parser.add_argument(
        "--qt-qml",
        type=Path,
        default=Path("/usr/lib/qt6/qml"),
        help="Qt 6 QML import root (Quickshell module)",
    )
    args = parser.parse_args()

    shell = args.shell.resolve() if args.shell else shell_root()
    if not shell.is_dir():
        raise SystemExit(f"Shell path is not a directory: {shell}")

    vfs = build_vfs(shell)
    ini = write_qmlls_ini(args.qt_qml.resolve())

    print(f"Shell QML: {shell}")
    print(f"VFS:       {vfs}")
    print(f"qmlls ini: {ini}")
    print("Restart the QML language server in Cursor (Qt: Restart QML Language Server).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
