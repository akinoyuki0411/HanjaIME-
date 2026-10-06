# 한지미 통합 설정 1.0.2

Separate settings/installation launcher for HanjiME Notch and HanjaIME. The application contains both signed local-development app bundles, shows their installation state, opens their existing settings, and installs missing components into the current user's Applications or Library/Input Methods directories. Existing app destinations are never overwritten. No administrator permission or network download is needed. Input-source selection remains a user action in macOS Keyboard settings; a logout/login may be necessary after registration.

Build: `python3 UnifiedSettings/build.py` after packaging the current NotchNext release. The script currently sources HanjaIME from the locally installed app, verifies signatures, and writes a temporary signed app path into build/unified-settings/app-path.txt. This is an Apple Silicon/macOS 14+ local development package, not a notarized public distribution.

Validation: both embedded payloads installed successfully into a temporary fixture directory, and a second install refused to overwrite each component. Tests did not change live input sources. Native UI confirmed both installed versions and opened both Notch and IME settings. Notch 1.0.2 build 10018 now uses content-specific window heights, cancels stale resize requests, constrains frames to the visible screen, and lets content follow the native window animation instead of jumping immediately to a fixed size. Native screenshots confirmed the smaller About window and larger Nook window, with intact layout.

Installed launcher: ~/Applications/Hanjimi Settings.app

Shareable local package: ~/Downloads/Hanjimi-Settings-1.0.2.zip
