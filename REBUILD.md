# Rebuilding and relinking

This package includes the macOS corresponding source used for the binary, including modified Gureum, libhangul-objc and libhangul. CorrespondingSource/SwiftPackages contains the exact Swift package checkouts used for the build. SDK and Xcode binaries are supplied separately by Apple.

On a compatible Mac with full Xcode, Python 3, Git and accepted Xcode terms:

```sh
source scripts/select_xcode.sh
hanjaime_select_xcode
python3 scripts/hanjaime.py build --source CorrespondingSource/gureum
```

The build resolves the exact Swift package revisions in Package.resolved, builds Release, runs native integration tests, embeds the notices, and signs ad-hoc. It may access the network to resolve packages. For offline development use Xcode local package overrides pointing to CorrespondingSource/SwiftPackages. The stock installer also prefers this corresponding-source snapshot when rebuilding.

Hangul.framework includes the static libhangul.a. The library, bridge and application source are supplied so recipients can modify the LGPL component and rebuild/relink the combined program. Do not prohibit reverse engineering for debugging such modifications.

The installer checks a fixed manifest to avoid accidental partial patches. After intentionally editing corresponding source, build the HanjaIME scheme directly in Xcode instead of trying to bypass the stock manifest. Use a new derived-data folder, macOS destination, your own signing or ad-hoc signing, no original development team. Personal-word management is compiled into GureumCore and hosted in the main application settings. There is no separate manager app. Preserve third-party notices. This is a development workflow, not a source-code restriction.

This release targets the build host architecture (Apple Silicon). Intel and older macOS versions need separate builds and tests. It is not Developer ID notarized.
