from pathlib import Path
import subprocess, shutil, plistlib, tempfile
root=Path(__file__).resolve().parent
app=Path(tempfile.mkdtemp(prefix='HanjaIME-Japanese-',dir='/private/tmp'))/'HanjaIME 日本語.app'
c=app/'Contents'; (c/'MacOS').mkdir(parents=True);(c/'Resources').mkdir()
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-target','arm64-apple-macosx12.0',*[str(p) for p in sorted((root/'Sources').glob('*.swift'))],'-o',str(c/'MacOS/HanjaIMEJapanese')],check=True)
for name in ['SKK-JISYO.L','SKK-JISYO.L.utf8','SKK-COPYING','OldForms.json','SOURCES.txt','AppIcon.icns','JapaneseInputIcon.icns','JapaneseMenu.png','JapaneseMenu@2x.png','JapaneseMenuSmall.png']:
 shutil.copy2(root/'Resources'/name,c/'Resources'/name)
identifier='org.hanjaime.inputmethod.Japanese';mode=identifier+'.hiragana'
info={'CFBundleIdentifier':identifier,'CFBundleName':'HanjaIME 日本語','CFBundleDisplayName':'HanjaIME 日本語','CFBundleExecutable':'HanjaIMEJapanese','CFBundlePackageType':'APPL','CFBundleDevelopmentRegion':'ko','CFBundleInfoDictionaryVersion':'6.0','CFBundleSupportedPlatforms':['MacOSX'],'CFBundleIconFile':'JapaneseInputIcon','CFBundleShortVersionString':'0.1.7','CFBundleVersion':'8','LSMinimumSystemVersion':'12.0','LSUIElement':True,'NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True,'InputMethodConnectionName':identifier+'_Connection','InputMethodServerControllerClass':'HanjaIMEJapaneseController','InputMethodServerDelegateClass':'HanjaIMEJapaneseController','TISInputSourceID':identifier,'TISIntendedLanguage':'ja','tsInputMethodIconFileKey':'JapaneseMenuSmall.png','tsInputMethodCharacterRepertoireKey':['Hira','Kana','Hani'],'ComponentInputModeDict':{'tsInputModeListKey':{'com.apple.inputmethod.Japanese':{'TISInputSourceID':mode,'TISIntendedLanguage':'ja','tsInputModeDefaultStateKey':True,'tsInputModeIsVisibleKey':True,'tsInputModePrimaryInScriptKey':True,'tsInputModeScriptKey':'smJapanese','tsInputModeMenuIconFileKey':'JapaneseMenu.png','tsInputModeAlternateMenuIconFileKey':'JapaneseMenu.png','tsInputModePaletteIconFileKey':'JapaneseMenu.png'}},'tsVisibleInputModeOrderedArrayKey':['com.apple.inputmethod.Japanese']},'NSHumanReadableCopyright':'HanjaIME 日本語; SKK dictionary GPL-2.0-or-later. See bundled notices.'}
# There is a single Japanese input source; do not create a separate parent/mode pair.
info.pop('ComponentInputModeDict')
info['tsInputModePrimaryInScriptKey']=True
info['CFBundleSignature']='HJjp'
(c/'PkgInfo').write_bytes(b'APPLHJjp')
(c/'Info.plist').write_bytes(plistlib.dumps(info))
for language in ['ja','ko','en']:
 folder=c/'Resources'/(language+'.lproj');folder.mkdir()
 (folder/'InfoPlist.strings').write_text('CFBundleDisplayName = "HanjaIME 日本語";\nCFBundleName = "HanjaIME 日本語";\n"'+mode+'" = "HanjaIME 日本語";\n"com.apple.inputmethod.Japanese" = "HanjaIME 日本語";\n')
 subprocess.run(['plutil','-lint',str(folder/'InfoPlist.strings')],check=True)
shutil.copytree(root/'Sources',c/'Resources/CorrespondingSource/Sources');shutil.copy2(root/'build.py',c/'Resources/CorrespondingSource/build.py')
subprocess.run(['xattr','-cr',str(app)],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-','--timestamp=none',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
(root/'app-path.txt').write_text(str(app));print(app)
