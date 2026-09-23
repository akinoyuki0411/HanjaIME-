#!/usr/bin/env python3
"""Developer helper: export deterministic text patches from a reviewed pinned checkout."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PIN = "5bdc5dc3df93d5a3aa61ad1df928d76bc903054b"
NEW = ["OSXCore/HanjaIMECandidatePanel.swift", "OSX/Icons/HanjaIME.png", "OSX/Icons/HanjaIME@2x.png",
       "OSXCore/HanjaIMECore.swift", "OSXCore/HanjaIMEComposer.swift", "OSXCore/HanjaIMEStorage.swift",
       "GureumTests/HanjaIMEIntegrationTests.swift",
       "Gureum.xcodeproj/xcshareddata/xcschemes/HanjaIME.xcscheme",
       "Gureum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    repo = parser.parse_args().repo.resolve()
    names = subprocess.check_output(["git", "diff", "--ignore-submodules=all", "--name-only", PIN], cwd=repo, text=True).splitlines()
    payload = []
    manifest = []
    for name in sorted(set(names + NEW)):
        old = subprocess.run(["git", "show", PIN + ":" + name], cwd=repo, capture_output=True)
        before = old.stdout if old.returncode == 0 else None
        after = (repo / name).read_bytes()
        if before == after:
            continue
        try:
            after_text = after.decode()
            before_text = (before or b"").decode()
            binary = b"\0" in after or b"\0" in (before or b"")
        except UnicodeDecodeError:
            binary = True
        if binary:
            diff = subprocess.check_output(["git", "diff", "--binary", "--full-index", PIN, "--", name], cwd=repo, text=True)
            if not diff:
                raise RuntimeError("Stage the new binary before exporting: " + name)
            # A public forward patch does not need the reverse binary payload,
            # which could redistribute the original noncommercial artwork.
            if "GIT binary patch\n" in diff:
                header, binary = diff.split("GIT binary patch\n", 1)
                diff = header + "GIT binary patch\n" + binary.split("\n\n", 1)[0] + "\n\n"
            payload.append(diff)
        else:
            diff = difflib.unified_diff(before_text.splitlines(keepends=True),
                                        after_text.splitlines(keepends=True),
                                        fromfile="a/" + name if before is not None else "/dev/null",
                                        tofile="b/" + name)
            payload.append("diff --git a/" + name + " b/" + name + "\n")
            if before is None:
                payload.append("new file mode 100644\n")
            payload.extend(diff)
        manifest.append({"path": name,
                         "before": hashlib.sha256(before).hexdigest() if before is not None else None,
                         "after": hashlib.sha256(after).hexdigest()})
    patch = "".join(payload).encode()
    (ROOT / "patches/gureum.patch").write_bytes(patch)
    (ROOT / "patches/manifest.json").write_text(json.dumps({
        "base_commit": PIN, "patch_sha256": hashlib.sha256(patch).hexdigest(), "files": manifest,
    }, indent=2) + "\n")
    print(f"Exported {len(manifest)} files, {len(patch)} patch bytes.")


if __name__ == "__main__":
    main()
