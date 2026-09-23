"""Evidence collection and bounded HanjaIME migration; no name-based deletion."""
import datetime as dt
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

from validate_input_modes import BUNDLE_ID, CURRENT_ID, DISPLAY_NAME

POLICY_PATH = Path(__file__).with_name("legacy_input_sources.json")
LSREGISTER = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")


def load_policy(path=POLICY_PATH):
    policy = json.loads(Path(path).read_text())
    legacy = policy["legacy_source_ids"]
    if (policy["bundle_id"] != BUNDLE_ID or policy["current_source_id"] != CURRENT_ID
            or not legacy or CURRENT_ID in legacy or BUNDLE_ID in legacy
            or any(not i.startswith(BUNDLE_ID + ".") for i in legacy)):
        raise ValueError("Unsafe migration policy")
    return policy


def is_legacy(row, policy):
    return (row.get("bundle_id") == policy["bundle_id"]
            and CURRENT_ID not in (row.get("source_id"), row.get("mode_id"))
            and any(row.get(key) in policy["legacy_source_ids"] for key in ("source_id", "mode_id")))


def is_related(row):
    # Diagnostic inclusion only. NEVER use names or this function to delete.
    return any(token in str(row.get(key, "")).lower()
               for key in ("name", "bundle_id", "source_id", "mode_id")
               for token in ("hanjaime", "hanjimi", "gureum", "han 2set"))


def is_independent_gureum(row):
    """Identify the separate Gureum product by IDs, never its display name."""
    bundle = "org.youknowone.inputmethod.Gureum"
    identifiers = [row.get(key) for key in ("source_id", "mode_id") if row.get(key)]
    return (row.get("bundle_id") == bundle and bool(identifiers)
            and all(value == bundle or value.startswith(bundle + ".") for value in identifiers))


def preference_is_legacy(item, policy):
    if isinstance(item, str):
        return item in policy["legacy_source_ids"]
    if not isinstance(item, dict):
        return False
    bundles = [item[k] for k in ("Bundle ID", "BundleID", "BundleIdentifier") if k in item]
    if any(b != BUNDLE_ID for b in bundles):
        return False
    ids = [item[k] for k in ("Input Mode", "InputMode", "InputModeID", "Input Source ID", "InputSourceID", "Source ID") if k in item]
    return CURRENT_ID not in ids and any(i in policy["legacy_source_ids"] for i in ids)


def version_tuple(value):
    parts = str(value).split(".")
    return tuple(int(x) for x in parts) if parts and all(x.isdecimal() for x in parts) else None


def under(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def bundle_record(path, roots, project, backup_root):
    path = Path(path).absolute()
    record = {"path": str(path), "exists": path.exists(), "classification": "other-copy"}
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        return dict(record, error="symlink; never mutate")
    if path.parent in roots:
        record["classification"] = "installed-input-method"
    elif under(path, backup_root):
        record["classification"] = "previous-installer-backup"
    elif under(path, project) or any(p.lower() in ("build", "dist", "deriveddata", "sourcepackages") or p.startswith("derived-") for p in path.parts):
        record["classification"] = "build-or-source-copy"
    try:
        info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        record.update(bundle_id=info.get("CFBundleIdentifier"), version=info.get("CFBundleShortVersionString"),
                      build=info.get("CFBundleVersion"), executable=info.get("CFBundleExecutable"),
                      connection=info.get("InputMethodConnectionName"), origin=info.get("HanjaIMEBuildOrigin"),
                      input_modes=info.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {}))
        record["owned"] = (record["bundle_id"] == BUNDLE_ID and record["executable"] == "HanjaIME"
                           and record["connection"] == "HanjaIME_Connection")
        record["writable"] = os.access(path, os.W_OK) and os.access(path.parent, os.W_OK)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        record["error"] = str(error)
    return record


def collect_bundles(snapshot, project, home=None):
    home = Path.home() if home is None else Path(home)
    roots = [home / "Library/Input Methods", Path("/Library/Input Methods")]
    backups = home / "Library/Application Support/HanjaIME/Backups"
    paths = set()
    observations = []
    for root in [*roots, backups]:
        try:
            paths.update(root.glob("*.app") if root in roots else root.glob("*/HanjaIME.app"))
            observations.append({"root": str(root), "exists": root.exists()})
        except OSError as error:
            observations.append({"root": str(root), "error": str(error)})
    for row in snapshot["sources"]:
        if is_related(row):
            paths.update(Path(url["path"]) for url in row.get("bundle_urls", []))
    if Path("/usr/bin/mdfind").is_file():
        queries = ["kMDItemFSName == '*Hanja*'c", "kMDItemFSName == '*Hanjimi*'c",
                   "kMDItemFSName == '*Gureum*'c", f"kMDItemCFBundleIdentifier == '{BUNDLE_ID}'"]
        for query in queries:
            result = subprocess.run(["/usr/bin/mdfind", query], capture_output=True, text=True, timeout=45)
            observations.append({"query": query, "status": result.returncode, "stderr": result.stderr})
            for line in result.stdout.splitlines():
                path = Path(line)
                if path.suffix == ".app":
                    paths.add(path)
    snapshot["bundle_scan"] = observations
    return [bundle_record(p, roots, Path(project), backups) for p in sorted(paths)]


def identity_report(snapshot):
    report = []
    bundles = {r["path"]: r for r in snapshot.get("bundles", [])}
    for source in snapshot["sources"]:
        if source.get("name", "").lower() != "han 2set":
            continue
        matches = [b for b in bundles.values() if b.get("bundle_id") == source.get("bundle_id") and b.get("exists")]
        exact = [b for b in matches if (source.get("mode_id") or source.get("source_id")) in b.get("input_modes", {})]
        reason = "undetermined: TIS has no public exact bundle URL; inspect candidates and registration history"
        if not matches:
            reason = "TIS row observed, no extant matching bundle found in scanned locations; cache-only is not yet proven"
        elif len(exact) == 1:
            reason = "one matching bundle/mode in the scan; this is evidence of a remaining bundle, not proof of TIS's backing URL"
        report.append(dict(source, matching_bundles=exact or matches, evidence=reason,
                           auto_cleanup_allowed=source.get("bundle_id") == BUNDLE_ID,
                           canonical_id_protected=CURRENT_ID in (source.get("source_id"), source.get("mode_id"))))
    return report


def retirement_plan(snapshot, target, new_info, source):
    new_version = version_tuple(new_info.get("CFBundleShortVersionString"))
    new_build = version_tuple(new_info.get("CFBundleVersion"))
    plan = []
    for record in snapshot.get("bundles", []):
        if not record.get("owned") or record.get("error") or not record.get("exists"):
            continue
        path = Path(record["path"])
        if path in (Path(target), Path(source)) or record["classification"] == "build-or-source-copy":
            continue
        old_version, old_build = version_tuple(record.get("version")), version_tuple(record.get("build"))
        if None in (new_version, new_build, old_version, old_build):
            action = "blocked-unverifiable-version"
        elif (old_version, old_build) > (new_version, new_build):
            action = "blocked-newer-version"
        elif not record.get("writable"):
            action = "blocked-filesystem-permission"
        else:
            action = "archive-and-unregister-exact-bundle"
        plan.append(dict(record, action=action))
    return plan


def archive_bundle(path, archive, run, remove=False):
    """Archive verified HanjaIME code without keeping a discoverable .app backup."""
    path, archive = Path(path), Path(archive)
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise RuntimeError("Refusing symlink bundle archive")
    info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "HanjaIME"
            or info.get("InputMethodConnectionName") != "HanjaIME_Connection"):
        raise RuntimeError("Refusing unrelated bundle archive")
    archive.parent.mkdir(parents=True, exist_ok=True)
    if archive.exists():
        raise RuntimeError("Backup already exists")
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", path, archive])
    with zipfile.ZipFile(archive) as z:
        if z.testzip() or z.read(path.name + "/Contents/Info.plist") != (path / "Contents/Info.plist").read_bytes():
            raise RuntimeError("Archive verification failed; original bundle retained")
    if remove:
        # lsregister -u is per bundle, NOT a LaunchServices database reset.
        # A failure retains the original and is reported, never silently ignored.
        if LSREGISTER.is_file():
            status, output = run([LSREGISTER, "-u", path], check=False, capture_status=True)
            # Only the exact scan failure observed for this already archived bundle
            # is recoverable. This does not prove absence from TIS or the Add UI.
            lines = [line.strip() for line in output.splitlines() if line.strip()]
            scan_missing = (status == 1 and lines in (
                [f"failed to scan {path}: -10814"],
                [f"failed to scan {path}: -10814", "from spotlight"]))
            archive.with_suffix(".lsregister.json").write_text(json.dumps({
                "bundle": str(path), "status": status, "output": output,
                "archived_scan_failure": scan_missing,
                "tis_absence_verified": False}, ensure_ascii=False, indent=2))
            if status and not scan_missing:
                raise RuntimeError("Bundle unregister failed; original retained: " + output)
            if scan_missing:
                print("백업 ZIP 검증 완료. 해당 백업의 -10814 scan 오류를 기록하고 정리를 계속합니다. TIS는 설치 후 별도 검증합니다.")
        shutil.rmtree(path)
    return archive


def registration_result(before, after, policy):
    def key(row):
        return (row.get("bundle_id"), row.get("source_id"), row.get("mode_id"))
    protected = {key(s) for s in before["sources"] if s.get("enabled") and s.get("bundle_id") != BUNDLE_ID}
    enabled_after = {key(s) for s in after["sources"] if s.get("enabled")}
    damaged = sorted(protected - enabled_after)
    owned = [s for s in after["sources"] if s.get("bundle_id") == BUNDLE_ID and s.get("select_capable")]
    canonical = [s for s in owned if s.get("source_id") == CURRENT_ID]
    legacy = [s for s in after["sources"] if is_legacy(s, policy)]
    unknown_owned = [s for s in owned if s.get("source_id") != CURRENT_ID and not is_legacy(s, policy)]
    old_names = [s for s in after["sources"] if is_related(s) and not is_independent_gureum(s) and
                 (s.get("name", "").lower() == "han 2set" or "english" in s.get("name", "").lower() or "영문" in s.get("name", ""))]
    # Independent Gureum remains usable; ambiguous identities still require investigation.
    independent = [s for s in after["sources"] if is_independent_gureum(s)]
    ok = (len(canonical) == 1 and canonical[0].get("enabled") and canonical[0].get("name") == DISPLAY_NAME
          and not legacy and not unknown_owned and not old_names and not damaged)
    return {"tis_registration_verified": bool(ok), "other_enabled_sources_preserved": not damaged,
            "missing_protected_sources": damaged, "canonical_sources": canonical,
            "legacy_still_available": legacy, "legacy_still_enabled": [s for s in legacy if s.get("enabled")],
            "independent_gureum_sources": independent,
            "unrecognized_owned_sources": unknown_owned, "unresolved_old_display_names": old_names,
            "system_settings_add_ui": "not-verified", "actual_application_input": "not-verified",
            "overall_user_acceptance": "pending-real-mac-UI-and-input-tests"}


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
