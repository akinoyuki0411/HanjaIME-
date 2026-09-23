#!/usr/bin/env python3
"""Build, stage, install, and recover HanjaIME without touching official Gureum."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_input_modes import validate_app
import input_source_migration as migration

VERSION = "0.9.4"
ROOT = Path(__file__).resolve().parent.parent
PIN = "5bdc5dc3df93d5a3aa61ad1df928d76bc903054b"
BUNDLE_ID = "org.hanjaime.inputmethod.HanjaIME"
BUILD = ROOT / "build"
DIST = ROOT / "dist"
ENV = os.environ.copy()
LOG = None


def note(message):
    print(message, flush=True)
    if LOG:
        LOG.write(message + "\n")
        LOG.flush()


def run(args, cwd=None, capture=False, check=True, capture_status=False):
    args = [str(a) for a in args]
    note("RUN " + repr(args))
    process = subprocess.Popen(args, cwd=cwd, env=ENV, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, errors="replace")
    lines = []
    for line in process.stdout:
        if capture or capture_status:
            lines.append(line)
        else:
            print(line, end="", flush=True)
        if LOG:
            LOG.write(line)
            LOG.flush()
    status = process.wait()
    process.stdout.close()
    if check and status:
        raise RuntimeError(f"명령 실패 (종료 코드 {status}): {args[0]}. 전체 로그에 원인이 기록되어 있습니다.")
    if capture_status:
        return status, "".join(lines)
    return "".join(lines) if capture else status


def mac_required():
    if sys.platform != "darwin":
        raise RuntimeError("이 환경은 macOS가 아닙니다. Xcode/InputMethodKit 빌드와 설치를 수행할 수 없습니다.")
    if os.getuid() == 0:
        raise RuntimeError("sudo로 실행하지 마세요. 사용할 Mac 계정에서 실행해야 합니다.")


def developer_environment():
    mac_required()
    # Keep the selected path separate from the helper's diagnostic messages.
    selection = subprocess.run(["/bin/bash", ROOT / "scripts/select_xcode.sh"],
                               env=ENV, capture_output=True, text=True)
    if selection.stderr.strip():
        note(selection.stderr.strip())
    if selection.returncode:
        raise RuntimeError("이 macOS에서 사용할 Xcode를 선택하지 못했습니다. 위 안내를 확인하세요.")
    if selection.stdout.strip():
        ENV["DEVELOPER_DIR"] = selection.stdout.strip()
    options = []
    if ENV.get("DEVELOPER_DIR"):
        options.append(Path(ENV["DEVELOPER_DIR"]))
    selected = subprocess.run(["/usr/bin/xcode-select", "-p"], capture_output=True, text=True)
    if selected.returncode == 0:
        options.append(Path(selected.stdout.strip()))
    options += [Path("/Applications/Xcode.app/Contents/Developer")]
    options += sorted(Path("/Applications").glob("Xcode*.app/Contents/Developer"))
    options += sorted((Path.home() / "Applications").glob("Xcode*.app/Contents/Developer"))
    for candidate in options:
        if (candidate / "usr/bin/xcodebuild").is_file():
            ENV["DEVELOPER_DIR"] = str(candidate)
            break
    else:
        raise RuntimeError("Xcode 전체 버전이 필요합니다. macOS 27에서는 developer.apple.com/download/의 Xcode 27 베타를 사용하세요. Xcode를 한 번 열어 약관과 추가 구성 요소 설치를 마친 뒤 다시 실행하세요.")
    run(["/usr/bin/xcodebuild", "-version"])
    run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"])
    for command in ["git", "python3"]:
        if not shutil.which(command):
            raise RuntimeError(f"필수 도구가 없습니다: {command}. Xcode 최초 실행을 완료해 주세요.")


def prepare_source():
    work = Path(tempfile.mkdtemp(prefix="source-", dir=BUILD))
    repo = work / "gureum"
    corresponding = ROOT / "CorrespondingSource/gureum"
    if corresponding.is_dir():
        shutil.copytree(corresponding, repo, symlinks=True)
        run([sys.executable, ROOT / "apply_hanjaime_patch.py", repo])
        return repo
    bundled = ROOT / "verification/upstream.bundle"
    source = str(bundled) if bundled.is_file() else "https://github.com/gureum/gureum.git"
    run(["git", "clone", "--no-checkout", source, repo])
    run(["git", "checkout", "--detach", PIN], cwd=repo)
    # Only the macOS dependency is needed. The unrelated iOS submodules are not initialized.
    run(["git", "submodule", "update", "--init", "--recursive", "libhangul-objc"], cwd=repo)
    run([sys.executable, ROOT / "apply_hanjaime_patch.py", repo])
    run(["git", "add", "-A"], cwd=repo)
    run(["git", "add", "-f", "Gureum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"], cwd=repo)
    run(["git", "-c", "user.name=HanjaIME local build", "-c", "user.email=build@local.invalid",
         "commit", "-m", f"Apply HanjaIME {VERSION} development patch"], cwd=repo)
    return repo


def bundle_info(app):
    app = Path(app)
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError(f"정상 앱 디렉터리가 아닙니다: {app}")
    with (app / "Contents/Info.plist").open("rb") as f:
        info = plistlib.load(f)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError(f"HanjaIME가 아닌 앱은 변경하지 않습니다: {app}")
    if info.get("CFBundleExecutable") != "HanjaIME":
        raise RuntimeError("앱 실행 파일 이름이 올바르지 않습니다.")
    if info.get("InputMethodConnectionName") != "HanjaIME_Connection":
        raise RuntimeError("InputMethodKit 연결 이름이 올바르지 않습니다.")
    return info


def verify(app, expected_version=None):
    info = bundle_info(app)
    if expected_version is not None and info.get("CFBundleShortVersionString") != expected_version:
        raise RuntimeError(f"앱 버전이 패키지 버전 {expected_version}과 일치하지 않습니다.")
    validate_app(app)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    executable = Path(app) / "Contents/MacOS/HanjaIME"
    if not executable.is_file():
        raise RuntimeError("앱 실행 파일이 없습니다.")
    run(["/usr/bin/lipo", "-info", executable])
    if not list(Path(app).glob("Contents/Frameworks/Hangul.framework/**/hanjaw.txt")):
        raise RuntimeError("한자 단어 사전이 앱에 포함되지 않았습니다.")


def sign(app):
    # xattr -d needs write permission even for absent attributes (SPM licenses
    # can be read-only). Restore original modes before signing nested code.
    permissions = []
    try:
        for path in [Path(app), *Path(app).rglob("*")]:
            if not path.is_symlink():
                mode = path.stat().st_mode & 0o7777
                if not mode & 0o200:
                    path.chmod(mode | 0o200)
                    permissions.append((path, mode))
        for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
            run(["/usr/bin/xattr", "-drs", attribute, app])
    finally:
        for path, mode in reversed(permissions):
            path.chmod(mode)
    # Sign nested code first. No Apple developer account, global Gatekeeper change, or sudo.
    for path in sorted(Path(app).rglob("*.dylib")):
        if not path.is_symlink():
            run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path])
    for path in sorted(Path(app).rglob("*.framework"), key=lambda p: -len(p.parts)):
        if not path.is_symlink():
            run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path])
    run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", app])


SYSTEM_APPLICATIONS = Path("/Applications")


def cleanup_legacy_manager_shortcuts(target):
    """Remove only symlinks to this IME's obsolete embedded manager; preserve other apps."""
    expected = (Path(target) / "Contents/Resources/HanjaIMEWordManager.app").resolve()
    removed = []
    for folder in [Path.home() / "Applications", SYSTEM_APPLICATIONS]:
        shortcut = folder / "HanjaIME Manager.app"
        if shortcut.is_symlink() and shortcut.resolve() == expected:
            shortcut.unlink()
            removed.append(str(shortcut))
    return removed


def settings():
    mac_required()
    installed = Path.home() / "Library/Input Methods/HanjaIME.app"
    if not installed.is_dir():
        raise RuntimeError("먼저 HanjaIME를 설치해 주세요.")
    run(["/usr/bin/open", "-a", installed, "--args", "--settings"])


def build(source=None):
    developer_environment()
    repo = Path(source).resolve() if source else prepare_source()
    if source:
        run([sys.executable, ROOT / "apply_hanjaime_patch.py", repo])
    derived = Path(tempfile.mkdtemp(prefix="derived-", dir=BUILD))
    common = ["/usr/bin/xcodebuild", "-project", repo / "Gureum.xcodeproj", "-scheme", "HanjaIME",
              "-derivedDataPath", derived, "-destination", "platform=macOS",
              "CODE_SIGN_ENTITLEMENTS=", "DEVELOPMENT_TEAM=", "MACOSX_DEPLOYMENT_TARGET=12.0",
              "ONLY_ACTIVE_ARCH=YES", "ENABLE_USER_SCRIPT_SANDBOXING=NO"]
    unsigned = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]
    test_signing = ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", "CODE_SIGN_IDENTITY=-",
                    "CODE_SIGN_STYLE=Manual", "ENABLE_HARDENED_RUNTIME=NO"]
    # Dependencies are exact revisions in the project and Package.resolved.
    run(common + unsigned + ["-resolvePackageDependencies", "-onlyUsePackageVersionsFromResolvedFile"], cwd=repo)
    run(common + unsigned + ["-configuration", "Release", "-disableAutomaticPackageResolution", "build"], cwd=repo)
    product = derived / "Build/Products/Release/HanjaIME.app"
    export = validate_app(product, repo / "OSX/Info.plist")
    migration.write_json(derived / "release-input-modes.json", export)
    run(common + test_signing + ["-configuration", "Debug", "-disableAutomaticPackageResolution", "test",
                  "-only-testing:OSXTests/HanjaIMEIntegrationTests",
                  "-resultBundlePath", derived / "HanjaIME-tests.xcresult"], cwd=repo)
    product = derived / "Build/Products/Release/HanjaIME.app"
    if not product.is_dir():
        raise RuntimeError("xcodebuild 후 HanjaIME.app을 찾을 수 없습니다.")
    notices = product / "Contents/Resources/HanjaIME-Licenses"
    shutil.copytree(ROOT / "licenses", notices, dirs_exist_ok=True)
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", notices)
    for checkout in (derived / "SourcePackages/checkouts").glob("*"):
        for license_file in checkout.iterdir():
            if license_file.is_file() and license_file.name.lower().startswith(("license", "copying")):
                shutil.copy2(license_file, notices / (checkout.name + "-" + license_file.name))
    DIST.mkdir(exist_ok=True)
    sign(product)
    verify(product, expected_version=VERSION)
    DIST.mkdir(exist_ok=True)
    completion = DIST / "build.json"
    if completion.exists():
        completion.rename(DIST / ("build-previous-" + uuid.uuid4().hex[:8] + ".json"))
    app = DIST / "HanjaIME.app"
    if app.exists():
        app.rename(DIST / ("HanjaIME-previous-" + uuid.uuid4().hex[:8] + ".app"))
    run(["/usr/bin/ditto", product, app])
    verify(app, expected_version=VERSION)
    helper = ensure_helper()
    (DIST / "build.json").write_text(json.dumps({
        "status": "macOS-build-and-integration-tests-passed", "app": str(app),
        "version": VERSION, "package_fingerprint": package_fingerprint(), "input_source_export": export,
        "source": str(repo), "base_commit": PIN, "built_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "gui_application_matrix": "not-run", "signing": "ad-hoc", "personal_words": "integrated-settings", "log": str(LOG.name),
    }, ensure_ascii=False, indent=2) + "\n")
    note(f"빌드·자동 테스트·서명 검증 완료. 설치 전 앱: {app}")
    return app


def package_fingerprint():
    digest = hashlib.sha256()
    for path in [ROOT / "patches/gureum.patch", *sorted((ROOT / "scripts").glob("*.py")),
                 ROOT / "scripts/register_input_source.swift", ROOT / "scripts/legacy_input_sources.json",
                 ROOT / "Sources/ConfigurationWindow.swift", ROOT / "Sources/HanjaIMEStorage.swift",
                 ROOT / "Sources/HanjaIMECore.swift"]:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def ensure_helper():
    # Source hashes prevent a previous release's helper silently skipping new
    # diagnostics/migration. Compile to a temporary file before replacing it.
    DIST.mkdir(exist_ok=True)
    source = ROOT / "scripts/register_input_source.swift"
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    helper = DIST / "register-input-source"
    stamp = DIST / "register-input-source.sha256"
    if not helper.is_file() or not stamp.is_file() or stamp.read_text().strip() != digest:
        temporary = DIST / ("register-input-source-" + uuid.uuid4().hex)
        try:
            run(["/usr/bin/xcrun", "swiftc", "-swift-version", "5", source,
                 "-framework", "Carbon", "-framework", "AppKit", "-o", temporary])
            temporary.replace(helper)
            stamp.write_text(digest + "\n")
        finally:
            temporary.unlink(missing_ok=True)
    return helper


def current_guard():
    helper = ensure_helper()
    run([helper, "--select-abc-if-needed"])
    result = run([helper, "--check-current"], check=False)
    if result:
        raise RuntimeError("기존 Apple 입력기로 전환하지 못했습니다. 설치본은 변경하지 않았습니다.")


def snapshot(helper, folder, label):
    # Store the raw dump first, so a later file scan failure cannot lose TIS data.
    data = json.loads(run([helper, "--dump"], capture=True))
    migration.write_json(folder / (label + "-tis-hitoolbox.json"), data)
    data["bundles"] = migration.collect_bundles(data, ROOT)
    data["han_2set_identity"] = migration.identity_report(data)
    migration.write_json(folder / (label + ".json"), data)
    migration.write_json(folder / (label + "-related-sources.json"),
                         [s for s in data["sources"] if migration.is_related(s)])
    return data


def diagnostic_folder():
    folder = BUILD / ("registration-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    folder.mkdir(parents=True)
    return folder


def diagnose():
    developer_environment()
    folder = diagnostic_folder()
    data = snapshot(ensure_helper(), folder, "before")
    migration.write_json(folder / "han-2set-identity.json", data["han_2set_identity"])
    note(f"TIS·HIToolbox·설치 경로 진단 저장: {folder}. 입력 소스는 변경하지 않았습니다.")


def verify_registration():
    developer_environment()
    folder = diagnostic_folder()
    after = snapshot(ensure_helper(), folder, "after")
    result = migration.registration_result(after, after, migration.load_policy())
    result["other_enabled_sources_preserved"] = "not-comparable-without-before-snapshot"
    migration.write_json(folder / "result.json", result)
    note(f"등록 재검사: {folder}")
    if not result["tis_registration_verified"]:
        raise RuntimeError("TIS에 구버전/미확인 항목이 남아 있습니다. result.json에 실제 ID를 기록했습니다.")
    note("TIS의 두벌식 단일 등록 확인. 시스템 설정 추가 화면과 실제 앱 입력은 별도 확인이 필요합니다.")


def paths():
    parent = Path.home() / "Library/Input Methods"
    parent.mkdir(parents=True, exist_ok=True)
    if parent.is_symlink():
        raise RuntimeError("Input Methods 디렉터리가 심볼릭 링크입니다. 자동 변경을 중단합니다.")
    backups = Path.home() / "Library/Application Support/HanjaIME/Backups"
    backups.mkdir(parents=True, exist_ok=True)
    return parent / "HanjaIME.app", backups


def backup_destination(backups):
    folder = backups / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    folder.mkdir()
    return folder / "HanjaIME.app"


def replace_app(source, target, backups):
    verify(source)
    if target.exists() or target.is_symlink():
        bundle_info(target)
    stage = Path(tempfile.mkdtemp(prefix=".HanjaIME-stage-", dir=target.parent))
    old = None
    try:
        staged = stage / "HanjaIME.app"
        run(["/usr/bin/ditto", source, staged])
        verify(staged)
        if target.exists():
            old = backup_destination(backups)
            target.rename(old)
        try:
            staged.rename(target)
        except BaseException:
            if old and old.exists() and not target.exists():
                old.rename(target)
            raise
    finally:
        shutil.rmtree(stage)
    # Only HanjaIME in the current user's session. Never kill Gureum.
    run(["/usr/bin/pkill", "-u", str(os.getuid()), "-x", "HanjaIME"], check=False)
    run([DIST / "register-input-source", "--register", target])
    if old:
        note(f"이전 HanjaIME 보존 위치: {old}")
    return old


def install():
    developer_environment()
    helper = ensure_helper()
    folder = diagnostic_folder()
    before = snapshot(helper, folder, "before")
    policy = migration.load_policy()
    app = DIST / "HanjaIME.app"
    completion = DIST / "build.json"
    metadata = json.loads(completion.read_text()) if completion.is_file() else {}
    if not app.is_dir() or metadata.get("package_fingerprint") != package_fingerprint():
        app = build()
    verify(app, expected_version=VERSION)
    migration.write_json(folder / "final-app-input-modes.json", validate_app(app))
    target, backups = paths()
    current_guard()
    plan = migration.retirement_plan(before, target, bundle_info(app), app)
    migration.write_json(folder / "migration-plan.json", plan)
    # Snapshot is durable before either TIS or file mutation.
    journal = []
    operation_completed = False
    operation_error = None
    try:
        run([helper, "--cleanup", migration.POLICY_PATH])
        for index, item in enumerate(plan):
            if item["action"] != "archive-and-unregister-exact-bundle":
                journal.append(item)
                continue
            original = Path(item["path"])
            info = bundle_info(original)
            if info.get("CFBundleShortVersionString") != item["version"] or info.get("CFBundleVersion") != item["build"]:
                raise RuntimeError(f"진단 이후 앱 버전이 변경되었습니다: {original}")
            archive = backups / folder.name / f"legacy-{index}-HanjaIME.zip"
            entry = {"original": str(original), "archive": str(archive), "state": "pending"}
            journal.append(entry)
            migration.write_json(folder / "migration-journal.json", journal)
            migration.archive_bundle(original, archive, run, remove=True)
            entry["state"] = "archived-and-retired"
            migration.write_json(folder / "migration-journal.json", journal)
        replaced_backup = replace_app(app, target, backups)
        # Old installers left .app backups discoverable by LaunchServices. Keep
        # verified ZIP backups instead; restore understands both generations.
        for old in ([replaced_backup] if replaced_backup else []):
            archive = old.parent / "HanjaIME-backup.zip"
            migration.archive_bundle(old, archive, run, remove=True)
            journal.append({"original": str(old), "archive": str(archive), "state": "archived-and-retired"})
        migration.write_json(folder / "migration-journal.json", journal)
        # Unregistering an old same-ID bundle can invalidate the component cache;
        # explicitly register the final canonical location again afterwards.
        run([helper, "--register", target])
        run([helper, "--enable-korean"])
        removed = cleanup_legacy_manager_shortcuts(target)
        note("개인 단어 관리: 한지미 설정 → 개인 단어. 이전 바로가기 정리: " + str(len(removed)))
        refresh = run(["/usr/bin/pkill", "-u", str(os.getuid()), "-x", "TextInputMenuAgent"], check=False)
        migration.write_json(folder / "refresh.json", {"process": "TextInputMenuAgent", "status": refresh})
        operation_completed = True
    except BaseException as error:
        operation_error = str(error)
        raise
    finally:
        after = snapshot(helper, folder, "after")
        result = migration.registration_result(before, after, policy)
        result["installation_operation_completed"] = operation_completed
        result["operation_error"] = operation_error
        if not operation_completed:
            result["tis_registration_verified"] = False
        result["blocked_bundle_actions"] = [p for p in plan if p["action"].startswith("blocked-")]
        if result["blocked_bundle_actions"]:
            result["tis_registration_verified"] = False
        migration.write_json(folder / "result.json", result)
        import difflib
        (folder / "before-after.diff").write_text("".join(difflib.unified_diff(
            json.dumps(before, ensure_ascii=False, indent=2, sort_keys=True).splitlines(True),
            json.dumps(after, ensure_ascii=False, indent=2, sort_keys=True).splitlines(True),
            fromfile="before", tofile="after")))
        note(f"설치 전후 TIS·HIToolbox·정리 기록: {folder}")
    if not result["tis_registration_verified"]:
        raise RuntimeError("앱 설치 후 등록 검증이 미완료입니다. result.json의 잔존 ID/경로를 확인하세요. "
                           "캐시만 남았다면 작업 저장 후 로그아웃·로그인하고 verify_input_sources.command를 실행하세요. "
                           "다른 입력기 설정은 초기화하지 않습니다.")
    note("앱 설치 및 TIS 두벌식 단일 등록 검사 통과. 완전 해결 판정은 아직 아닙니다.")
    note("시스템 설정의 입력 소스 추가 목록과 TextEdit/Safari/Spotlight/Finder 입력을 확인하세요. "
         "HanjaIME 두벌식에서 dkssudgktpdy → 안녕하세요가 되어야 합니다.")


def uninstall():
    mac_required()
    target, backups = paths()
    if not target.exists() and not target.is_symlink():
        note("설치된 HanjaIME가 없습니다. 공식 Gureum은 그대로 유지됩니다.")
        return
    bundle_info(target)
    current_guard()
    destination = backup_destination(backups).with_name("HanjaIME-backup.zip")
    migration.archive_bundle(target, destination, run, remove=True)
    run(["/usr/bin/pkill", "-u", str(os.getuid()), "-x", "HanjaIME"], check=False)
    note(f"HanjaIME 앱 제거 완료. 앱은 {destination}에 보존했습니다. 학습 데이터도 보존됩니다.")
    note("시스템 설정의 입력 소스 목록에서 HanjaIME를 제거하세요.")


def restore():
    mac_required()
    target, backups = paths()
    candidates = sorted([*backups.glob("*/HanjaIME.app"), *backups.glob("*/HanjaIME-backup.zip")],
                        key=lambda p: p.parent.name, reverse=True)
    if not candidates:
        raise RuntimeError("복원할 HanjaIME 백업이 없습니다.")
    developer_environment()
    with tempfile.TemporaryDirectory(prefix="restore-", dir=BUILD) as directory:
        source = candidates[0]
        if source.suffix == ".zip":
            import zipfile
            with zipfile.ZipFile(source) as archive:
                if archive.testzip() or any(Path(n).is_absolute() or ".." in Path(n).parts for n in archive.namelist()):
                    raise RuntimeError("안전한 백업 ZIP이 아닙니다.")
            run(["/usr/bin/ditto", "-x", "-k", source, directory])
            source = Path(directory) / "HanjaIME.app"
        # Do not restore a release that reintroduces retired modes/names.
        verify(source)
        current_guard()
        replace_app(source, target, backups)
    note("이전 두벌식 단일 입력기 복원 완료. verify_input_sources.command로 등록을 재검사하세요.")


def main():
    global LOG
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["build", "install", "uninstall", "restore", "doctor", "settings", "diagnose", "verify-registration"])
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    logfile = BUILD / (args.action + "-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6] + ".log")
    lock = BUILD / "operation.lock"
    lockfile = None
    with logfile.open("w", encoding="utf-8") as LOG:
        try:
            lockfile = lock.open("a+")
            fcntl.flock(lockfile.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            lockfile.seek(0)
            lockfile.truncate()
            lockfile.write(str(os.getpid()) + "\n")
            lockfile.flush()
            note(f"HanjaIME {VERSION} 개발판 | {sys.platform} | 작업 로그: {logfile}")
            if args.action == "build":
                build(args.source)
            elif args.action == "doctor":
                developer_environment()
            elif args.action == "diagnose":
                diagnose()
            elif args.action == "verify-registration":
                verify_registration()
            elif args.action == "settings":
                settings()
            else:
                {"install": install, "uninstall": uninstall, "restore": restore}[args.action]()
        except BlockingIOError:
            note("다른 HanjaIME 작업이 실행 중입니다. 해당 작업이 끝난 뒤 다시 실행하세요.")
            return 1
        except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
            note(f"중단: {error}")
            note(f"전체 로그: {logfile}")
            return 1
        finally:
            if lockfile:
                lockfile.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
