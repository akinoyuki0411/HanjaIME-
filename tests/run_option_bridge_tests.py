"""Compile production key routing and Hangul methods against real libhangul on Linux.
AppKit flags/client and HGInputContext are small adapters; this does not exercise macOS UI.
"""
import argparse
from pathlib import Path
import re
import subprocess
ROOT=Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--swiftc',type=Path,required=True);p.add_argument('--optimize',action='store_true');a=p.parse_args()
src=a.source.resolve()
def without_imports(text):return re.sub(r'^import .*\n','',text,flags=re.M)
def method(text,name):
    start=text.index('  func '+name+'('); opening=text.index('{',start); end=opening+1;depth=1
    while depth:
        if text[end]=='{':depth+=1
        if text[end]=='}':depth-=1
        end+=1
    return text[start:end]
intro=r'''
import Foundation
import CHangul
public enum NSEvent {
 public struct ModifierFlags: OptionSet {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue=rawValue }
  static let capsLock=Self(rawValue: 1<<16), shift=Self(rawValue: 1<<17), control=Self(rawValue: 1<<18)
  static let option=Self(rawValue: 1<<19), command=Self(rawValue: 1<<20), numericPad=Self(rawValue: 1<<21), function=Self(rawValue: 1<<23)
 }
}
protocol IMKTextInput: AnyObject {}
protocol IMKUnicodeTextInput: AnyObject {}
final class Client: IMKTextInput, IMKUnicodeTextInput {}
enum InputAction: Equatable { case none, commit, cancel }
struct InputResult {
 let processed: Bool
 let action: InputAction
 static let processed=Self(processed: true,action: .none)
 static let notProcessed=Self(processed: false,action: .none)
}
final class Configuration {
 static let shared=Configuration()
 var lastHangulInputMode=""
 var optionKeyBehavior=1
 var hangulDeferredSymbolCommit=false
 var hangulWonCurrencySymbolForBackQuote=true
 var hangulForceStrictCombinationRule=false
 func object(forKey: String) -> Any? { nil }
 func set(_ value: Any, forKey: String) {}
}
let debugInputReceiver=false
func dlog(_ enabled: Bool, _ format: String, _ values: Any...) {}
typealias HGUCSChar=UInt32
func HGCharacterIsChoseong(_ value: UInt32) -> Bool { hangul_is_choseong(value) }
extension NSString {
 convenience init(ucsString: [UInt32]) {
  self.init(string: String(String.UnicodeScalarView(ucsString.prefix { $0 != 0 }.compactMap(UnicodeScalar.init))))
 }
 convenience init(ucsString: UnsafePointer<UInt32>) { self.init(string: RealHangulBuffer.string(ucsString)) }
}
final class HGInputContext {
 let raw=hangul_ic_new("2")!
 var preeditUCSString: UnsafePointer<UInt32> { hangul_ic_get_preedit_string(raw)! }
 var commitUCSString: UnsafePointer<UInt32> { hangul_ic_get_commit_string(raw)! }
 func flushUCSString() -> UnsafePointer<UInt32> { hangul_ic_flush(raw)! }
 func reset() { hangul_ic_reset(raw) }
 static var rejectNext = false
 func process(_ key: UInt32) -> Bool {
  if Self.rejectNext {
   Self.rejectNext = false
   _ = hangul_ic_process(raw,32) // failure flushes the preceding native preedit
   return false
  }
  return hangul_ic_process(raw,Int32(key))
 }
 func backspace() -> Bool { hangul_ic_backspace(raw) }
 func setKeyboardWithIdentifier(_ id: String) { hangul_ic_select_keyboard(raw,id.replacingOccurrences(of: "-full", with: "")) }
 deinit { hangul_ic_delete(raw) }
}
'''
h=(src/'OSXCore/HangulComposer.swift').read_text()
helpers=without_imports(h[:h.index('// MARK: - HangulComposer')])
hangul='''
final class HangulComposer: Composer, HanjaIMEHangulBuffer {
 private var configuredKeyboard="2-full"
 private var optionYetMode=false
 private var _commitString="", _composedString=""
 let inputContext=HGInputContext()
 let configuration=Configuration.shared
 var composedString: String { _composedString + representableString(ucsString: inputContext.preeditUCSString) }
 var commitString: String { _commitString }
 func clear() { clearCompositionContext() }
'''
for name in ['dequeueCommitString','cancelComposition','clearCompositionContext','input','setKeyboard','inputYetKey','prepareKoreanKeyboard']:
    hangul+=method(h,name)+'\n'
start=h.index('  private func endOptionYetMode(');end=h.index('\n  func inputYetKey',start)
hangul+=h[start:end]+'\n}\n'
g=(src/'OSXCore/GureumComposer.swift').read_text()
gureum='''
final class RomanComposer: Composer {
 func map(text: String?,key: KeyCode,modifiers: NSEvent.ModifierFlags) -> String? { "LATIN_MAPPER_MUST_NOT_RUN" }
}
enum GureumInputSource: String {
 case han2="org.hanjaime.inputmethod.HanjaIME.han2"
 var keyboardIdentifier: String { "2-full" }
}
final class SearchComposer { func cancelSearch() {} }
final class GureumComposer {
 var delegate: Composer!
 var hanjaComposer: HanjaIMEComposer!
 var hangulComposer: HangulComposer!
 let searchComposer=SearchComposer()
 var _inputMode=GureumInputSource.han2.rawValue
 let systemRomanComposer=RomanComposer(), qwertyComposer=RomanComposer()
 var romanComposer: RomanComposer { systemRomanComposer }
 func cancelAndCommit() { fatalError("legacy Roman branch reached") }
 func enqueueCommitString(_ value: String) { fatalError("Roman output reached") }
'''+method(g,'synchronizeSelectedMode')+'\n'+method(g,'input')+'\n}\n'
# Execute the production alternate IMK entry point too. The old implementation
# existed only in MockInputController, so direct composer tests could miss it.
controller=(src/'OSXCore/InputController.swift').read_text().split('@objcMembers public class MockInputController')[0]
start=controller.index('  public override func inputText(')
opening=controller.index('{', start); end=opening+1; depth=1
while depth:
    if controller[end]=='{':depth+=1
    if controller[end]=='}':depth-=1
    end+=1
callback=controller[start:end]
receiver=(src/'OSXCore/InputReceiver.swift').read_text()
entrypoint='''
class IMKInputControllerAdapter {
 func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any) -> Bool { false }
}
final class InputReceiverAdapter {
 let composer: GureumComposer
 var lastClient: AnyObject?
 init(_ composer: GureumComposer) { self.composer=composer }
 func input(text: String?, key: KeyCode, modifiers: NSEvent.ModifierFlags,
            client: IMKTextInput & IMKUnicodeTextInput) -> InputResult {
  lastClient=client
  return input2(text:text,keyCode:key,modifiers:modifiers,client:client)
 }
'''+method(receiver,'input2')+'''
}
final class InputControllerAdapter: IMKInputControllerAdapter {
 let receiver: InputReceiverAdapter
 init(_ composer: GureumComposer) { receiver=InputReceiverAdapter(composer) }
 func asClient(_ sender: Any) -> IMKTextInput & IMKUnicodeTextInput {
  sender as! (IMKTextInput & IMKUnicodeTextInput)
 }
'''+callback+'\n}\n'
hanja=(src/'OSXCore/HanjaIMEComposer.swift').read_text()
hanja=hanja[hanja.index('final class HanjaIMEExactDictionary'):hanja.index('\npublic enum HanjaIMEControls')]
lookup='''
final class HGKeyboard: NSObject {}
final class ListLifetime {}
final class HGHanja {
 weak var owner: ListLifetime?
 let raw: OpaquePointer
 let index: UInt32
 init(owner: ListLifetime,raw: OpaquePointer,index: UInt32) { self.owner=owner;self.raw=raw;self.index=index }
 func read(_ getter: (OpaquePointer?,UInt32) -> UnsafePointer<CChar>?) -> String {
  precondition(owner != nil,"Borrowed Hanja accessed after owning list was freed")
  return String(cString:getter(raw,index)!)
 }
 var key: String { read(hanja_list_get_nth_key) }
 var value: String { read(hanja_list_get_nth_value) }
 var comment: String { read(hanja_list_get_nth_comment) }
}
final class HGHanjaList {
 let owner=ListLifetime()
 let raw: OpaquePointer
 let array: [HGHanja]
 init(_ list: OpaquePointer) {
  raw=list
  let lifetime=owner
  array=(0..<hanja_list_get_size(list)).map { index in
   HGHanja(owner:lifetime,raw:list,index:UInt32(index))
  }
 }
 deinit { hanja_list_delete(raw) }
}
final class HGHanjaTable {
 let raw: OpaquePointer
 init?(contentOfFile path: String) { guard let raw=hanja_table_load(path) else { return nil }; self.raw=raw }
 func hanjas(byPrefixSearching reading: String) -> HGHanjaList? {
  hanja_table_search_prefix(raw,reading).map(HGHanjaList.init)
 }
 deinit { hanja_table_delete(raw) }
}
struct HanjaTableSearchSource {
 enum Method { case exact }
 let table: HGHanjaTable, method: Method
 struct Candidate { let value: String, description: String }
 struct Result { let candidate: Candidate }
 func collect(_ reading: String,workItem: DispatchWorkItem) -> [Result] {
  guard let list=hanja_table_match_exact(table.raw,reading) else { return [] }
  let owner=HGHanjaList(list)
  return withExtendedLifetime(owner) {
   owner.array.map { Result(candidate: Candidate(value:$0.value,description:$0.comment)) }
  }
 }
}
'''
tests=r'''
@main struct OptionBridgeTests {
 static var checks=0
 static func expect(_ value: @autoclosure () -> Bool,_ message: String) {
  checks+=1
  if !value() { fputs("FAIL: "+message+"\n",stderr); exit(1) }
 }
 static func main() {
  let defaults=UserDefaults(suiteName:"org.hanjaime.optionbridge."+UUID().uuidString)!
  let usage=HanjaIMEUsageStore(defaults: defaults)
  let client=Client(), hangul=HangulComposer(), router=GureumComposer()
  let dictionary=HanjaIMEExactDictionary(directory:URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent())
  let composer=HanjaIMEComposer(hangul:hangul,usage:usage,dictionary:dictionary)
  router.delegate=composer
  router.hanjaComposer=composer
  router.hangulComposer=hangul
  let controller=InputControllerAdapter(router)
  for staleText: String? in [nil, "", "LATIN_FALLBACK", "é"] {
   composer.clear()
   let field=Client()
   for letter in "dkssudgktpdy" {
    let key=keyMapReversed[String(letter)]!.0
    expect(controller.inputText(staleText,key:key.rawValue,modifiers:0,client:field),
      "production keyed IMK entry consumes the physical Korean key")
   }
   expect(controller.receiver.lastClient === field,"text callback routes the current field")
   expect(composer.composedString=="안녕하세요","keyed callback composes Korean independent of raw text")
   expect(!controller.inputText("a",key:KeyCode.ansiA.rawValue,
     modifiers:Int(NSEvent.ModifierFlags.command.rawValue),client:field),"Command is passed through at the receiver boundary")
   expect(!controller.inputText("a",key:KeyCode.ansiA.rawValue,
     modifiers:Int(NSEvent.ModifierFlags.control.rawValue),client:field),"Control is passed through at the receiver boundary")
  }
  func input(_ key: KeyCode,_ flags: NSEvent.ModifierFlags = [],_ text: String? = nil) -> Bool {
   router.input(text:text,key:key,modifiers:flags,client:client).processed
  }
  func type(_ text: String) {
   for key in text {
    let mapped=keyMapReversed[String(key)]!
    expect(input(mapped.0,mapped.1,String(key)),"Korean key handled")
   }
  }
  composer.clear(); type("dk")
  HGInputContext.rejectNext = true
  expect(input(.ansiA,.option),"rejected Option key retries Korean instead of leaking Latin")
  expect(composer.composedString=="아ㅁ","Option recovery preserves the previous syllable and current key")
  composer.clear(); type("dk")
  HGInputContext.rejectNext = true
  expect(input(.ansiA),"native two-set rejection retries built-in Korean")
  expect(composer.composedString=="아ㅁ","Korean recovery preserves flushed syllable and new letter")
  composer.clear()
  Configuration.shared.hangulDeferredSymbolCommit = true
  type("dk")
  HGInputContext.rejectNext = true
  _ = hangul.input(text:";",key:.ansiSemicolon,modifiers:[],client:client)
  expect(hangul.dequeueCommitString()=="아","deferred unhandled key preserves native flushed syllable")
  Configuration.shared.hangulDeferredSymbolCommit = false
  composer.clear()
  for keyboard in ["ro", "3f", "2y-full"] {
   composer.clear()
   hangul.setKeyboard(identifier:keyboard)
   type("dkssudgktpdy")
   expect(composer.composedString=="안녕하세요","Korean path repairs a stale keyboard: \(keyboard)")
  }
  // Execute the actual production reconciliation and physical-key methods,
  // including a deliberately corrupted legacy delegate, with real libhangul.
  for stale in ["qwerty","system","dvorak","colemak"] {
   composer.clear()
   router.delegate=RomanComposer()
   router.synchronizeSelectedMode("org.hanjaime.inputmethod.HanjaIME."+stale)
   expect(router.delegate is HanjaIMEComposer,"stale delegate repaired: \(stale)")
   type("dkssudgktpdy")
   expect(composer.composedString=="안녕하세요","legacy event still composes Korean")
   expect(composer.dequeueCommitString().isEmpty,"repair never enqueues raw Latin")
   composer.clear();type("d")
   router.synchronizeSelectedMode("org.hanjaime.inputmethod.HanjaIME."+stale)
   type("kssudgktpdy")
   expect(composer.composedString=="안녕하세요","notification never splits initial syllable")
  }
  composer.clear()
  router.delegate=RomanComposer()
  type("dkssudgktpdy")
  expect(router.delegate is HanjaIMEComposer && composer.composedString=="안녕하세요",
         "input guard repairs without any TIS notification")
  for behavior in [0,1] {
   Configuration.shared.optionKeyBehavior=behavior
   for flags: NSEvent.ModifierFlags in [.option,[.option,.shift],[.option,.capsLock]] {
    for key in "abcdefghijklmnopqrstuvwxyz" {
     composer.clear()
     expect(input(keyMapReversed[String(key)]!.0,flags,"LatinFallback"),"Option consumed \(key)")
     let output=composer.composedString+composer.dequeueCommitString()
     expect(!output.isEmpty,"Option emits text \(key)")
     expect(output.range(of:"[A-Za-z]",options:.regularExpression)==nil,"Option never emits Latin \(key): \(output)")
    }
   }
  }
  composer.clear();type("r")
  expect(input(.ansiK,.option),"Option K below-a")
  type("s")
  expect(composer.composedString=="ᄀᆞᆫ","old Hangul syllable: \(composer.composedString)")
  expect(input(.return),"old Hangul Enter")
  expect(composer.dequeueCommitString()=="ᄀᆞᆫ","old Hangul commit")
  type("rk");_ = input(.return)
  expect(composer.dequeueCommitString()=="가","modern layout restored")
  for (key,expected) in [(KeyCode.ansiA,UInt32(0x1140)),(.ansiD,0x114c),(.ansiG,0x1159),(.ansiK,0x119e),(.ansiL,0x1194)] {
   composer.clear();_ = input(key,.option)
   expect(composer.composedString.decomposedStringWithCompatibilityMapping.unicodeScalars.contains { $0.value==expected },"canonical 2y position \(key)")
  }
  composer.clear();type("durtk")
  expect(input(.ansiSemicolon,.option),"ellipsis consumed")
  expect(composer.composedString=="역사…","literal retains the full marked session")
  expect(composer.dequeueCommitString().isEmpty,"literal does not prematurely commit")
  expect(input(.return),"Enter commits literal session")
  expect(composer.dequeueCommitString()=="역사…","last syllable preserved")
  composer.clear();type("dkssudgktpdy")
  expect(composer.composedString=="안녕하세요","modern greeting unaffected")
  expect(!input(.ansiE,[.option,.command]),"Command Option remains host shortcut")
  expect(composer.dequeueCommitString()=="안녕하세요","shortcut flushes complete text")
  for (keys,expected) in [("durtk","歷史"),("wjdcl","政治"),("tktkd","思想"),("dusrn","硏究"),("wprnr","帝國"),("eogksalsrnr","大韓民國"),("dkssudgktpdy","安寧하세요")] {
   composer.clear(); type(keys)
   expect(composer.session.candidates.first?.value==expected,"exact/inflected candidate precedes prefixes: \\(expected), got \\(composer.session.candidates.prefix(3))")
   _ = input(.space)
   expect(composer.composedString==expected,"preview preserves all syllables")
   _ = input(.return)
   expect(composer.dequeueCommitString()==expected,"commit preserves preview")
  }
  usage.reset()
  composer.clear();type("durtk");_ = input(.downArrow);_ = input(.downArrow)
  expect(composer.composedString=="役事","second exact candidate remains reachable before predictions")
  _ = input(.return)
  expect(composer.dequeueCommitString()=="役事","arrow selection commits exact alternative")
  expect(usage.snapshot(reading:"역사")["役事"]==1,"selected alternative learned")
  composer.clear();type("durtk")
  expect(composer.session.candidates.first?.value=="役事","personal learning outranks default exact candidate")
  usage.reset()
  composer.clear();type("durtk");_ = input(.space);type("fmf")
  expect(composer.composedString=="歷史를","inline candidate retains prefix before particle")
  _ = input(.space)
  expect(composer.composedString=="歷史를 ","particle plus space remains marked")
  composer.clear();type("durtk");_ = input(.ansiLeftBracket);type("wjdcl");_ = input(.space);type("rk")
  expect(composer.composedString=="역사「政治가","sentence prefix survives inline acceptance")
  composer.clear();type("dkssudgktpdy");_ = input(.space);_ = input(.space,.shift)
  expect(composer.composedString=="안녕하세요 ","Shift Space restores Hangul preview")
  expect(usage.snapshot(reading:"안녕").isEmpty,"cancelled preview is not learned")
  composer.clear();type("durtk");_ = input(.ansiLeftBracket);_ = input(.space);_ = input(.return)
  expect(composer.dequeueCommitString()=="역사」","related symbol selection replaces only symbol")
  composer.clear();type("wl")
  expect(composer.session.candidates.first?.value=="地圖","frequent prediction for short prefix")
  expect(composer.session.candidates.contains { $0.value=="地" },"exact single Hanja remains accessible")
  expect(dictionary.predictions("역사").contains { $0.value=="歷史家" },"real dictionary prefix lookup exercised")
  expect(dictionary.predictions("역사").allSatisfy { $0.value != "歷史" },"exact words excluded from predictions")
  usage.flush()
  print("PASS: \(checks) production Option-routing/libhangul checks; AppKit adapters only")
 }
}
'''
output=ROOT/'build/option-tests';output.mkdir(parents=True,exist_ok=True)
corehelpers=(ROOT/'tests/CoreTests.swift').read_text().split('@main struct CoreTests')[0]
payload=intro+without_imports((src/'OSXCore/KeyCode.swift').read_text())+without_imports((src/'OSXCore/Composer.swift').read_text())+without_imports(corehelpers)+helpers+hangul+lookup+hanja+gureum+entrypoint+tests
swift=output/'OptionBridge.swift';swift.write_text(payload)
native=ROOT/'build/portable-tests/libhangul/hangul';headers=sorted((a.swiftc.parent.parent/'lib/clang').glob('*/include/stddef.h'))
cmd=[a.swiftc,'-swift-version','5','-I',ROOT/'build/portable-tests/CHangul','-Xcc','-I'+str(headers[-1].parent),'-L',native,'-lhangul','-Xlinker','-rpath','-Xlinker',native,ROOT/'Sources/HanjaIMEStorage.swift',ROOT/'Sources/HanjaIMECore.swift',swift,'-o',output/'option-tests']
if a.optimize: cmd.append('-O')
subprocess.run(list(map(str,cmd)),check=True)
subprocess.run([str(output/'option-tests'),str(src/'OSXCore/data/hanja/hanjaw.txt')],check=True)
