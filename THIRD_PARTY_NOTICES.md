# Third-party notices

HanjaIME is derived from Gureum. Original copyright and license notices remain in licenses and CorrespondingSource. HanjaIME is a separate modified input method, not an official Gureum release.

- Gureum: BSD-style license; licenses/Gureum-BSD.txt.
- libhangul and libhangul-objc: LGPL 2.1 family; licenses/libhangul-LGPL.txt and Hangul-bridge.txt. Complete macOS source and relinking instructions accompany this package.
- Hanja dictionary: licenses/Hanja-dictionary-BSD.txt.
- Korean emoji keywords: Unicode CLDR release-48 annotations/ko.xml and annotationsDerived/ko.xml, Unicode License v3, licenses/Unicode-3.0.txt. Additional Korean associations were curated for this release. Generated data are in Data/emoji-ko.tsv and embedded in HanjaIMECore.swift.
- MASShortcut, SwiftUp and Fuse: exact resolved sources and upstream licenses in CorrespondingSource/SwiftPackages. The application also includes their license notices.
- HanjaIME glyph graphics were generated using Noto under OFL. See licenses/Noto-OFL.txt. No font binary is included.

Original Gureum artwork covered by the separate noncommercial license is excluded/replaced by HanjaIME graphics, including unused macOS resource references. Historical upstream notices are retained for provenance. Apple emoji fonts or images are not bundled; the OS renders Unicode characters.

The licenses above apply to their respective components. This notice does not select a new license for the distributor's original HanjaIME additions. Recipients must be permitted to modify/relink the LGPL components and reverse engineer for debugging those modifications. See REBUILD.md and 판매와후원_라이선스검토.md before redistribution.

Naver fallback loads the official NAVER Dictionary web page in an ephemeral WKWebView after Apple Dictionary has no result. NAVER and its content suppliers retain all rights. No dictionary text is scraped, packaged or relicensed by HanjaIME. Network queries can be disabled in settings. UI screenshots supplied as design references are not bundled.
