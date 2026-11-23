"""Compile the declared addon package and run isolated Lua 5.1 behavior checks.

Install test-only dependency outside the addon:
    python -m pip install --target scratch/toolchain/python lupa==2.6
Run from any directory:
    python tests/run_lua.py

This does not emulate WoW's protected frames, item movement, or renderer.
"""
from pathlib import Path
import argparse
import sys


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path, default=root / "scratch/toolchain/python")
    parser.add_argument("--syntax-only", action="store_true")
    options = parser.parse_args()
    sys.path.insert(0, str(options.lupa_path.resolve()))
    try:
        from lupa.lua51 import LuaRuntime, LuaError
    except ImportError:
        print("Install lupa==2.6 in scratch/toolchain/python, or specify --lupa-path.", file=sys.stderr)
        return 2

    package = root / "src/ForTheHoard"
    toc = package / "ForTheHoard.toc"
    if not toc.is_file():
        parser.error(f"Expected addon manifest: {toc}")
    declared = []
    for line in toc.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = (package / line).resolve()
        if not path.is_relative_to(package.resolve()) or not path.is_file():
            parser.error(f"Invalid or missing TOC member: {line}")
        declared.append(path)
    sources = sorted(package.rglob("*.lua"))
    if set(sources) != set(declared) or len(declared) != len(set(declared)):
        parser.error("Every addon Lua source must be declared exactly once in the TOC")
    tests = sorted(path for path in (root / "tests").glob("*.lua") if not path.stem.endswith("_helper"))
    if not tests and not options.syntax_only:
        parser.error("No behavior checks found")

    runtime = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = runtime.eval("function(text, name) local chunk, err = loadstring(text, name); if not chunk then error(err, 0) end end")
    failures = []
    for path in [*sources, *tests]:
        try:
            compile_lua(path.read_text(encoding="utf-8-sig"), "@" + path.as_posix())
        except (LuaError, OSError) as error:
            failures.append(f"SYNTAX {path.name}: {error}")
    ran = 0
    if not failures and not options.syntax_only:
        for path in tests:
            runtime = LuaRuntime(unpack_returned_tuples=True)
            runtime.globals().REPO_ROOT = root.as_posix()
            try:
                runtime.eval("function(path) local f, err = loadfile(path); if not f then error(err, 0) end; return f() end")(path.as_posix())
                runtime.execute("io.stdout:flush(); io.stderr:flush()")
                print(f"PASS {path.name}", flush=True)
            except (LuaError, OSError) as error:
                failures.append(f"FAIL {path.name}: {error}")
            ran += 1
    for failure in failures:
        print(failure, file=sys.stderr)
    print(f"Lua 5.1: {len(sources)} addon files, {ran} behavior suites, {len(failures)} failures.")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
