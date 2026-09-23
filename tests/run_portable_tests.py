#!/usr/bin/env python3
"""Developer-only portable core test runner; the Mac app uses its Xcode tests."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="Gureum checkout including libhangul-objc/libhangul")
    parser.add_argument("--swiftc", default=shutil.which("swiftc"))
    parser.add_argument("--cmake", default=shutil.which("cmake"))
    args = parser.parse_args()
    if not args.swiftc or not args.cmake:
        parser.error("Swift compiler and CMake are required for portable tests.")
    source = args.source.resolve()
    output = ROOT / "build/portable-tests"
    module = output / "CHangul"
    module.mkdir(parents=True, exist_ok=True)
    library = source / "libhangul-objc/libhangul"
    native = output / "libhangul"
    def run(argv):
        subprocess.run([str(a) for a in argv], check=True)
    run([args.cmake, "-S", library, "-B", native, "-DENABLE_EXTERNAL_KEYBOARDS=OFF",
         "-DBUILD_TESTING=OFF", "-DENABLE_UNIT_TEST=OFF", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"])
    run([args.cmake, "--build", native, "--target", "hangul", "-j", "2"])
    (module / "module.modulemap").write_text('module CHangul [system] {\n header "' + str(library / "hangul/hangul.h") + '"\n export *\n}\n')
    compiler = Path(args.swiftc).absolute()
    args_clang = []
    # Some standalone Linux toolchains don't discover their bundled C resource headers.
    resources = sorted((compiler.parent.parent / "lib/clang").glob("*/include/stddef.h"))
    if resources:
        args_clang = ["-Xcc", "-I" + str(resources[-1].parent)]
    run([compiler, "-swift-version", "5", "-warnings-as-errors", *args_clang,
         "-I", module, "-L", native / "hangul", "-lhangul", "-Xlinker", "-rpath", "-Xlinker", native / "hangul",
         ROOT / "Sources/HanjaIMEStorage.swift", ROOT / "Sources/HanjaIMECore.swift", ROOT / "tests/CoreTests.swift", "-o", output / "core-tests"])
    run([output / "core-tests", source / "OSXCore/data/hanja/hanjaw.txt"])


if __name__ == "__main__":
    main()
