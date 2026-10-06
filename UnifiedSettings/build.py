from pathlib import Path
import subprocess,shutil,plistlib,tempfile
root=Path(__file__).resolve().parents[1]
app=Path(tempfile.mkdtemp(prefix='Hanjimi-Settings-',dir='/private/tmp'))/'Hanjimi Settings.app'
if app.exists(): shutil.rmtree(app)
c=app/'Contents'; (c/'MacOS').mkdir(parents=True); (c/'Resources/Payloads').mkdir(parents=True)
subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-O','-target','arm64-apple-macosx14.0',str(root/'UnifiedSettings/Sources/App.swift'),'-o',str(c/'MacOS/HanjimiSettings')],check=True)
notch=Path((root/'build/notch-rebuild/preview-path.txt').read_text().strip())
ime=Path.home()/'Library/Input Methods/HanjaIME.app'
japanese=Path((root/"JapaneseIME/app-path.txt").read_text().strip())
for src in [notch,ime,japanese]:
 subprocess.run(['codesign','--verify','--deep','--strict',str(src)],check=True)
 shutil.copytree(src,c/'Resources/Payloads'/src.name,symlinks=True)
shutil.copy2(root/'UnifiedSettings/Resources/AppIcon.icns',c/'Resources/AppIcon.icns')
info={'CFBundleIdentifier':'org.hanjaime.UnifiedSettings','CFBundleName':'Hanjimi Settings','CFBundleDisplayName':'한지미 통합 설정','CFBundleExecutable':'HanjimiSettings','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0.3','CFBundleVersion':'10027','LSMinimumSystemVersion':'14.0','CFBundleIconFile':'AppIcon','NSHighResolutionCapable':True}
(c/'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['xattr','-cr',str(app)],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-','--timestamp=none',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)

(root/'build/unified-settings/app-path.txt').write_text(str(app))
