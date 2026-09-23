# HanjaIME 0.9.4

A Korean 2-set input method for macOS, based on Gureum and libhangul. Type Korean and choose Hanja, Japanese character forms or related emoji.

## Install and use

Download the release ZIP, extract it into a new folder, and run `repair_and_install.command`. The current installer may build and validate the app using Xcode and its command-line tools. Select **HanjaIME 두벌식** in macOS Input Sources. Log out and back in if it does not appear immediately.

Open the input menu → Settings → General → English. This changes the interface language; the keyboard remains Korean 2-set. Space selects/cycles candidates; Enter commits; Shift+Space preserves Hangul and inserts a space; Esc cancels conversion. Manage your own entries in Settings → My Words.

Settings → About offers GitHub release checks and verified ZIP downloads. Automatic checks are opt-in and occur daily. Install the downloaded ZIP manually. What's New appears once on the first launch of each newer version.

This is an Apple Silicon development-signed build, not Developer ID notarized. Gureum remains installed separately. The installed app lives in `~/Library/Input Methods/HanjaIME.app`.

Contact: akinoyuki0122@gmail.com · [Issues](https://github.com/akinoyuki0411/HanjaIME-/issues) · [Source](https://github.com/akinoyuki0411/HanjaIME-). Donations are not open yet.

Personal words and learning history stay on your Mac and are not included in releases. Naver lookup sends only the selected dictionary term when requested. Optional update checks contact GitHub. See THIRD_PARTY_NOTICES.md, licenses/ and CorrespondingSource/ for licenses and corresponding source.
