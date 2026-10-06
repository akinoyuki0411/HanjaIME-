# HanjiME Face 0.9.6 — local research build

This is experimental webcam authentication, not Apple Face ID. It is not approved for public distribution or relied upon as a validated authentication factor.

## Implemented

- Separate `org.hanjaime.face` process; the keyboard and notch do not receive passwords or templates.
- Explicit enrollment with macOS owner authentication, camera permission, local camera preview and nine guided head poses with two stable observations per direction.
- SFace embeddings stored in a dedicated local Keychain item; no enrollment image files or biometric logs.
- User-entered password stored in a separate Keychain item after owner authentication. Saving does not verify that the password is correct.
- Default off on every launch. Separate consent and owner authentication before enabling.
- Temporal center/turn/center challenge, matching against every enrolled sample, timeout and failed-challenge retry suppression for the current session.
- Automatic input requires the current console user's session, a focused empty secure field owned by the Apple-signed system loginwindow, and a fullscreen loginwindow surface at screensaver level or above. Inaccessible or missing evidence blocks input.
- Target revalidation and PID-targeted public CGEvent input, with no global HID fallback, private API, Secure Input bypass, or FileVault support.
- One password submission attempt per recognized lock session. Posting events is not reported as proof of successful unlock.
- Stop cancels pending owner authentication, camera capture and the polling timer. A stale authentication completion cannot re-enable the service.

## Verified in this development session

- Native face worker builds from OpenCV; the real models reject a synthetic blank frame.
- Sixteen policy checks cover invalid embeddings, unrelated vectors, timing challenge, target/enable gate, and duplicate attempts. These are synthetic policy checks, not biometric accuracy measurements.
- A read-only live test rejects the ordinary desktop as an unlock target. No password is supplied or typed by this test.
- Manager, notch and face service Release build succeeded. The locally staged bundle passes ad-hoc signature verification.
- UI opens the separate service; default off, empty credential field and disabled enable button were observed.
- User reported camera light without a usable enrollment flow. Added local preview, a face guide, sample progress, explicit owner-authentication/camera status and registration presence checks.
- Registration status subsequently showed a saved password and no accessible face template. Credential values were not read by the development tools.

## Not yet verified

- Successful enrollment after the preview change; true/false accept rates across people, poses and lighting; photo/video/deepfake resistance.
- The challenge is only a heuristic, not proven liveness. The 0.65 threshold is experimental.
- Actual lockscreen Accessibility visibility, permission setup and end-to-end unlock on this Mac. Code compilation and event posting do not prove this.
- Lock-screen challenge guidance, camera orientation/direction usability, and robust multiuser/session-switch coverage.
- FileVault initial login is intentionally unsupported.
- Keychain buffers use normal Swift/Foundation allocations; best-effort buffer clearing is not a guarantee that every copy is erased from memory.

## Distribution boundary

Local model assets are development inputs under `build/face-deps`, not checked-in distributable resources. OpenCV Zoo model licenses are preserved, but model-weight/training-data commercial distribution scope still needs review. No Glance or NotchNook assets are included. No commit, push, tag or release has been performed.

## 2026-09-28 notch registration update

Enrollment now opens in a dedicated top-anchored notch panel rather than a settings sheet. The green ring, directions and completion/failure flow remain in the Face process. A short-lived display reservation makes the utility notch yield and recover. Release build and 33 enrollment / 5 layout checks pass. The opening UI was inspected without starting the camera; real biometric enrollment remains deferred by user request.

Final native validation also passed six presentation checks: utility windows hide during enrollment, competing AI opens are blocked while reserved, windows restore afterwards, and the active application is unchanged. CUA verified the final green start button, top-anchored registration window and return to settings via Later. No camera or real password-input test was performed on 2026-09-28.

## 2026-09-28 Mirror and diagnostics follow-up
- Positive OpenCV sample: Vision detected one face with pitch; native YuNet/SFace worker returned 128 dimensions in 0.18 s. This verifies the fixture pipeline, not user camera accuracy.
- Preview connection explicitly mirrored; recognition output explicitly unmirrored; Vision revision 3 pinned for pitch.
- Enrollment now distinguishes camera/pose/worker/model failures instead of labeling every failure as darkness. Root cause on the user camera remains unconfirmed pending a real enrollment attempt.
- Notch now exposes existing calendar (explicit permission), local audio player, and quick notes through Widgets. No system-wide Now Playing support claimed. Removed idle audio polling in favor of playback completion callback.
- Inspected installed NotchNook 1.5.5 bundle metadata: menu-bar app with calendar, music, Bluetooth and mirror capabilities. Requested ZIP paths were absent; no proprietary source/assets incorporated.
- Release build passed; notch 36, enrollment 33, face policy 16 checks passed. New signed local preview: /private/tmp/HanjiME-096-MirrorWidgets/HanjiME.app. No release or push.

## 2026-09-30 restart
- Restored a standalone local app at ~/Applications/HanjiME Face.app, without reinstalling retired manager/old notch/keyboard apps.
- Added explicit recognition-test mode. It reads the enrolled face template after owner authentication, requests camera access, evaluates the existing movement challenge, and ends before any password read, UnlockDriver input or lock-session claim. Existing automatic input remains default off and separately consented.
- Added transient camera pipeline stages (video, face, pose, embedding) to enrollment/settings so 0/9 reports can distinguish missing frames from later analysis failures. No images, embeddings or pose values are logged.
- Release build succeeded; final installed bundle re-signed outside cloud-synced build folder and strict/deep verification passed. 16 synthetic face-policy and 38 enrollment checks passed. Native UI entry/exit to registration verified without starting enrollment.
- Current UI reports face unregistered or inaccessible, existing password present. Password contents were not read, changed or supplied. Actual enrollment, recognition and lockscreen unlock remain unverified.
- Scope: custom webcam matching is not a LocalAuthentication biometric provider. Apple Pay, Apple passkeys, other apps' Touch ID prompts and FileVault initial login are not implemented or claimed. See Apple's LocalAuthentication documentation and Platform Security biometric uses documentation.

## 2026-10-01 integrated presentation
Face is now packaged as a helper inside HanjiME Notch, with explicit URL routes for enrollment, recognition testing and settings. Integrated mode removes the standalone status item. Enrollment closes the ordinary notch using a short-lived presentation lease, restores the originating UI on close, and preserves process separation for biometrics/passwords. Native entry and exit were verified without camera capture. No new claim of real-world recognition accuracy or lockscreen unlock.

### 2026-10-01 — 0/9 inference diagnosis
- Installed worker processed the repository's OpenCV sample through the same Foundation Process/BGRA pipe protocol in approximately 0.16 seconds, yielding a valid normalized 128-element vector. No user face or credential was accessed for this fixture.
- Worker now distinguishes no face, multiple faces, and face too small. Swift validates/decodes each response, explicitly rejects malformed or invalid vectors, and displays a stable waiting state with actionable text instead of overwriting failures with per-frame 'analyzing' messages.
- Security thresholds and required stable poses unchanged. No automatic input enabled.
- 11 response decoder checks, 16 policy checks, 38 enrollment-guide checks passed. Blank BGRA frame produces face_not_found. Face Release build and embedded app packaging passed.
- Fresh enrollment intro opened in the installed integrated helper; user asked to complete owner authentication and report real capture progress. The user's 0/9 cause and end-to-end enrollment success are not yet confirmed.

Follow-up in the same session:
- Native AX during user's actual enrollment showed: '지원하지 않는 카메라 영상 크기입니다.' This identified rejection of actual capture dimensions before inference (requested VGA preset was not sufficient).
- FaceCapture now fits actual BGRA frames into 640×480 using vImage, preserving aspect ratio and respecting source row stride. Raw and converted data remain in memory. Source dimensions are bounded; thresholds remain unchanged.
- New camera-frame integration test runs the actual infer path without starting a camera, using an OpenCV sample. Clear centered crops at 640×480, 1920×1080 and 3840×2160 all returned valid embeddings. An initial small-face/letterboxed fixture was correctly rejected; testing a clear centered crop isolates resizing from detector quality.
- Reply+sizing tests now 18 passed. Updated Face Release build and installed strict signature verification passed. Asked user to retry actual enrollment with the correction; completion still pending.

Actual camera follow-up:
- After installing the camera-size correction, native AX confirmed real enrollment reached 7/9. This verifies the prior 0/9 format rejection was cleared on the user's camera.
- A subsequent run reached 6/9 and failed the existing same-face score gate. Changed enrollment-only mismatch handling to reject that frame and reset pose stability while preserving completed samples, with a less-turn/move-slowly hint. Every stored sample still must meet the original identity threshold; authentication challenge failure behavior unchanged. Release rebuilt and installed with signature verification.
- Current intro reopened. Full 9/9 registration and later recognition test not yet confirmed.

Registration result:
- After the enrollment-only frame retry correction, native AX changed from active 6/9 to the helper settings reporting '얼굴: 등록됨 · 비밀번호: 저장됨'. The prior state was unregistered; this confirms actual registration was saved through the completed guide.
- Started non-password recognition test. Later UI returned to '자동 입력 꺼짐' with no success result visible. Do not claim recognition-test or system unlock success; no automatic input was enabled by the agent.
