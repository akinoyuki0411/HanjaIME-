#!/usr/bin/env python3
"""Build a local review app; not a public-release packaging script."""
import os,pathlib,shutil,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
build=root/'.build/release'
output=pathlib.Path(tempfile.mkdtemp(prefix='HanjiME-Notch-Rebuild-',dir='/private/tmp'))/'HanjiME Notch.app'
contents=output/'Contents'
for name in ['MacOS','Resources','Frameworks']:(contents/name).mkdir(parents=True)
shutil.copy2(build/'Atoll',contents/'MacOS/Atoll')
shutil.copy2(root/'Resources/Info.plist',contents/'Info.plist')
shutil.copy2(root/'Resources/AppIcon.icns',contents/'Resources/AppIcon.icns')
shutil.copytree(build/'Atoll_Atoll.bundle',contents/'Resources/Atoll_Atoll.bundle',symlinks=True)
shutil.copytree(root/'../build/notch-rebuild/media-build/MediaRemoteAdapter.framework',contents/'Frameworks/MediaRemoteAdapter.framework',symlinks=True)
shutil.copy2(root/'ThirdParty/MediaRemoteAdapter/bin/mediaremote-adapter.pl',contents/'Resources/mediaremote-adapter.pl')
shutil.copy2(root/'ThirdParty/MediaRemoteAdapter/LICENSE',contents/'Resources/MediaRemoteAdapter-BSD-3-Clause.txt')
shutil.copy2(root/'LICENSE',contents/'Resources/Atoll-MIT.txt')
face_source = root/'../build/face-restart/Build/Products/Release/HanjiME Face.app'
if not face_source.exists():
    raise SystemExit('Build the HanjiMEFace Release target into build/face-restart before packaging.')
face_target = contents/'Helpers/HanjiME Face.app'
shutil.copytree(face_source, face_target, symlinks=True)
shutil.copytree(root/'../FaceUnlock/Licenses', face_target/'Contents/Resources/Licenses', dirs_exist_ok=True)
subprocess.run(['install_name_tool','-add_rpath','@executable_path/../Frameworks',str(contents/'MacOS/Atoll')],check=True)
subprocess.run(['xattr','-cr',str(output)],check=True)
identity = os.environ.get('HANJIME_NOTCH_SIGNING_IDENTITY', '-').strip()
if not identity:
    raise SystemExit('HANJIME_NOTCH_SIGNING_IDENTITY must name an existing code-signing identity.')
if identity == '-':
    print('Local ad-hoc build: macOS permissions may need reapproval after replacing this version.')
# A supplied identity must already exist; never create/trust certificates or
# fall back silently when signing fails.
subprocess.run(['codesign','--force','--deep','--sign',identity,'--timestamp=none',str(output)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(output)],check=True)
(root/'../build/notch-rebuild/preview-path.txt').write_text(str(output))
print(output)
