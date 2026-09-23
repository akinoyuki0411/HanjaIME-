#!/usr/bin/env python3
"""Update known Fix4 launchers, backing them up; never rebuild or edit dist."""
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
LEGACY_HASHES = {
    "install_hanjaime.command": "bfc312407dcf51d14b8deec928340ac2b3427f7f489e64298ef3b578212fa289",
    "restore_hanjaime.command": "e96b68ac5b3689bcd5022296fdcd9c8d1720f9353155576c3d5c2e8b41d30024",
}
SUPPORT_HASHES = {
    # The repair helper remains usable with the original Fix4 support file and
    # with reviewed package revisions. This repair changes launchers only.
    "scripts/hanjaime.py": {
        "bff3e5ca60c83cfb10d67d7cd24f76d5deb1386614958fee2e56c288cbb81c63",  # 0.9.4 public source
        "1273c76cd1f7303f44b6f78deda445c0825886e2654e926165e731f18dd0c18d",  # 0.8.14 international
        "d6e31bbdc91345cca28e7e0510717209e7db82dc89fd04bb9adf803afa389116",  # 0.8.13 liquid settings
        "42b5191f2096e112148edd290a7601c71f768415621e44f2c31b9aa66e6d1924",  # 0.8.12 integrated settings
        "3c90f601df58bc5788bd3546289ffb3e31a5707098867770dce38152ee6e4309",  # 0.8.11 public distribution
        "711b2a1bd5e3e48104580b636a60256c79bddb064cda20a46eb516ad443c78fd",  # 0.8.9 verified app version
        "01b628c5d3b0c91e6d961bab57dd62653cf132c27017d7f98c5d9b29a1bc1c26",  # 0.8.9 signing metadata cleanup
        "03922f6a28bdafddd41d84843405cf5d1672cdf7fca52b050b0899f2f36dc4ff",  # 0.8.9 macOS xattr cleanup
        "afdb841af15a7b04498becb2d416b3e4cf424251dc3d9114aed3ae77808ed643",  # 0.8.9 release verification, preserving restore
        "64914ab4f102d9ec39c6b3d193d904916de4cc9f2a57dcc9e45bdb520540fa10",  # 0.8.9 read-only license metadata cleanup
        "5c98613c49e514b63c80fffddf4d5168860d002ada0b4b4e95c72117b3cb50c8",  # 0.8.10 candidate fixes
        "37b014d2265cdf60c7ba80499ad4c6d9e9e7b8f90f2b5ce859dc0cc651054262",  # 0.8.8 second-word candidate frame fallback
        "d47afb03115956e750d2e205af3c00aaec7400619713afa09302b3cc2a3d0340",  # 0.8.7 second-word candidate panel anchor recovery
        "ec06cce64029177f79358bad2baa136bed71d302b712ceaf467126a647b408b5",  # 0.8.6 manager install
        "b83e12fb059221f6acc5209abc129c223f7e045b6eb2390382b0b734b91b3731",  # 0.8.4 Xcode 27 build fix
        "1bf1d5a50fc0226a3560d18a7f141fd2e0bd48c6a7328e008535afce35730fd1",  # 0.8.5 integration test compile fix
        "e7fe89105d1a8578ec3c6412471c2f031583b0808db39fc70138740f98e82987",  # 0.8.3 reviewed manager embedding and logging
        "e836a1cb827c6731447d5bea067bc96b37e5dac9716c801ac3f405ca6020991a",  # reviewed archive scan handling
        "2f510fec2c6f41d9bc7caeb46fa6066daed5c7c850e60d5fb476646f3367f33d",  # 0.8.2 reviewed scoped registration migration
        "ff73826064deeb18ab84a412d686bde9f9e3ed3dbbae6c889bf763649153ae6e",  # 0.8.1 release labels
        "5e09557237f870074209af58fc4d0685e5285ca2da38474277f009caae6c3912",  # 0.8: release labels
        "f93cefa3d1a267a254a8d21c3a1e31bb06c6011009fcc74ec42a5d601a7871e1",  # 0.7.4: release labels
        "c5f448c10eaad12d04f239c1b5705b71ca1d1cf212d2b611599d10d4ac2b8b8b",  # 0.7.3: manager compiler flag and release labels
        "935e341efd99ea2f7abe58e9baf01a156eacd0bf38dbdb14721c7087a474b754",  # 0.6: release labels only
        "a9c72dc9aaf92e54b67405e9b2ec1bf6904c40cd084c22bbc084673513357f74",
        "2fc7267ccccfa01dffdb25e1f733d9eb7fbd68c95c04355af2dc70ddc2597f53",
        "5fddf3f5999bc66afa00330dd228680305f396ec065b5efda327f9f92856aaa2",
        "4541af90309bb4140cfc083bde216e86980ea55ccc26057ef664aa195193a44c",  # 0.7.1: release labels only
        "f437dc242c2bf5c5ba05094ea141566e54a5f47f1e53c29dadb84f6a43162d0d",  # 0.7.2: release labels only
    },
    "scripts/select_xcode.sh": {
        "1914902fdc0dde0d5c5298d2a020e3165c53bc3bb53e591cb8accd08fe4cf371",
    },
}


def regular_bytes(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"정상 파일이 아닙니다: {path}")
    return path.read_bytes()


def replace_file(source, target):
    descriptor, name = tempfile.mkstemp(prefix=".hanjaime-repair-", dir=target.parent)
    os.close(descriptor)
    temporary = Path(name)
    try:
        shutil.copy2(source, temporary)
        temporary.replace(target)
    finally:
        if temporary.exists():
            temporary.unlink()


def repair(project):
    project = Path(project).resolve()
    for name, expected in SUPPORT_HASHES.items():
        if hashlib.sha256(regular_bytes(project / name)).hexdigest() not in expected:
            raise RuntimeError(f"예상한 Fix4 파일과 다릅니다. 덮어쓰지 않습니다: {name}")
    app = project / "dist/HanjaIME.app"
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError("기존 빌드의 HanjaIME.app을 찾을 수 없습니다.")
    info = plistlib.loads(regular_bytes(app / "Contents/Info.plist"))
    if (info.get("CFBundleIdentifier") != "org.hanjaime.inputmethod.HanjaIME"
            or info.get("CFBundleExecutable") != "HanjaIME"):
        raise RuntimeError("선택한 앱이 HanjaIME가 아닙니다.")
    completion = json.loads(regular_bytes(project / "dist/build.json"))
    if completion.get("status") != "macOS-build-and-integration-tests-passed":
        raise RuntimeError("빌드·자동 테스트 성공 기록이 없습니다. 앱을 다시 만들거나 설치하지 않았습니다.")
    helper = project / "dist/register-input-source"
    if helper.is_symlink() or not helper.is_file() or not os.access(helper, os.X_OK):
        raise RuntimeError("입력 소스 등록 도구가 없습니다. 기존 빌드 폴더 전체를 선택해 주세요.")

    build = project / "build"
    if build.is_symlink():
        raise RuntimeError("build가 심볼릭 링크입니다. 자동 수정을 중단합니다.")
    build.mkdir(exist_ok=True)
    lock_path = build / "operation.lock"
    if lock_path.is_symlink():
        raise RuntimeError("작업 잠금 파일이 심볼릭 링크입니다. 자동 수정을 중단합니다.")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        pending = []
        for name, expected in LEGACY_HASHES.items():
            current = regular_bytes(project / name)
            replacement = regular_bytes(ROOT / name)
            if current == replacement:
                continue
            if hashlib.sha256(current).hexdigest() != expected:
                raise RuntimeError(f"직접 변경된 실행 파일은 덮어쓰지 않습니다: {name}")
            pending.append(name)
        if not pending:
            print("설치 실행기는 이미 수정되어 있습니다.", flush=True)
            return None
        backup = build / ("installer-backup-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S")
                          + "-" + uuid.uuid4().hex[:8])
        backup.mkdir()
        for name in pending:
            shutil.copy2(project / name, backup / name)
        print(f"원본 실행 파일 백업: {backup}", flush=True)
        changed = []
        try:
            for name in pending:
                replace_file(ROOT / name, project / name)
                changed.append(name)
        except BaseException:
            for name in reversed(changed):
                replace_file(backup / name, project / name)
            raise
        (backup / "repair.json").write_text(json.dumps({
            "fix": "select-Xcode-before-install-and-restore", "files": pending,
            "app_rebuilt": False, "dist_modified": False,
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("설치·복원 실행기의 Xcode 선택을 수정했습니다. 기존 빌드 결과를 사용합니다.", flush=True)
        return backup


def main():
    try:
        if sys.platform != "darwin":
            raise RuntimeError("빌드에 성공한 Mac에서 실행해 주세요.")
        if os.getuid() == 0:
            raise RuntimeError("sudo 없이 사용할 Mac 계정에서 실행해 주세요.")
        if len(sys.argv) != 2:
            raise RuntimeError("repair_existing_install.command를 더블클릭해 주세요.")
        repair(sys.argv[1])
    except BlockingIOError:
        print("다른 HanjaIME 작업이 실행 중입니다. 해당 작업이 끝난 뒤 다시 실행해 주세요.", flush=True)
        return 1
    except (RuntimeError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"설치 수정 중단: {error}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
