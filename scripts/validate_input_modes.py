#!/usr/bin/env python3
"""Validate the *built* bundle, including localization and resource exports."""
import argparse
import json
from pathlib import Path
import plistlib
import re

BUNDLE_ID = "org.hanjaime.inputmethod.HanjaIME"
CURRENT_ID = BUNDLE_ID + ".han2"
DISPLAY_NAME = "HanjaIME 두벌식"


def read_strings(path):
    data = Path(path).read_bytes()
    try:
        return plistlib.loads(data)
    except plistlib.InvalidFileException:
        encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
        text = data.decode(encoding)
        pairs = re.findall(r'(?:"([^"\n]+)"|([A-Za-z0-9_.-]+))\s*=\s*"([^"\n]*)"\s*;', text)
        return {quoted or bare: value for quoted, bare, value in pairs}


def validate_info(info, built=True):
    errors = []
    if built and info.get("CFBundleIdentifier") != BUNDLE_ID:
        errors.append("unexpected bundle identifier")
    component = info.get("ComponentInputModeDict", {})
    modes = component.get("tsInputModeListKey", {})
    if set(modes) != {CURRENT_ID}:
        errors.append("export must contain exactly the canonical han2 mode")
    if component.get("tsVisibleInputModeOrderedArrayKey") != [CURRENT_ID]:
        errors.append("visible mode order must contain only han2")
    mode = modes.get(CURRENT_ID, {})
    if mode.get("TISInputSourceID") != CURRENT_ID or mode.get("TISIntendedLanguage") != "ko":
        errors.append("canonical source must use its own ID and Korean language")
    for key in ("tsInputModeIsVisibleKey", "tsInputModeDefaultStateKey"):
        if mode.get(key) is not True:
            errors.append(key + " must be true")
    if info.get("TISInputSourceID") != BUNDLE_ID or info.get("TISIntendedLanguage") != "ko":
        errors.append("invalid component source/language")
    exported = json.dumps(component, ensure_ascii=False).lower()
    for suffix in ("qwerty", "system", "dvorak", "colemak", "english", "영문", "han 2set"):
        if suffix in exported:
            errors.append("retired mode in export: " + suffix)
    if errors:
        raise ValueError("Invalid HanjaIME input source export: " + "; ".join(errors))
    return modes


def validate_app(app, source_info=None):
    app = Path(app)
    with (app / "Contents/Info.plist").open("rb") as f:
        info = plistlib.load(f)
    modes = validate_info(info)
    resources = app / "Contents/Resources"
    names = {}
    for locale in ("ko", "en"):
        strings = read_strings(resources / (locale + ".lproj") / "InfoPlist.strings")
        if strings.get(CURRENT_ID) != DISPLAY_NAME:
            raise ValueError(f"{locale}: input source name must be {DISPLAY_NAME}")
        if any(name in str(strings).lower() for name in ("hanjaime english", "hanjaime 영문", "hanjimi english", "han 2set")):
            raise ValueError("Retired localized input source name: " + locale)
        names[locale] = strings[CURRENT_ID]
    if list(resources.rglob("HanjaIMEEnglish*")):
        raise ValueError("Unused HanjaIME English icon still bundled")
    if source_info:
        with Path(source_info).open("rb") as f:
            source = plistlib.load(f)
        validate_info(source, built=False)
        if source["ComponentInputModeDict"] != info["ComponentInputModeDict"]:
            raise ValueError("Xcode changed the patched source's input mode export")
    return {"app": str(app), "bundle_id": info["CFBundleIdentifier"],
            "version": info.get("CFBundleShortVersionString"),
            "input_modes": list(modes), "display_names": names}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("app", type=Path)
    p.add_argument("--source-info", type=Path)
    args = p.parse_args()
    print(json.dumps(validate_app(args.app, args.source_info), ensure_ascii=False, indent=2))
