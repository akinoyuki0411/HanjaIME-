"""Run production commit/render methods on a UTF-16 document model, not AppKit."""
import argparse
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--swiftc',type=Path,required=True)
a=parser.parse_args()
s=(a.source/'OSXCore/InputReceiver.swift').read_text()
def method(name):
 start=s.index('  func '+name+'(')
 opening=s.index('{',start)
 end=opening+1; depth=1
 while depth:
  if s[end]=='{': depth+=1
  elif s[end]=='}': depth-=1
  end+=1
 return s[start:end]
prefix=r'''
import Foundation
import CHangul
protocol IMKTextInput: AnyObject {
 func markedRange() -> NSRange
 func insertText(_ text: String, replacementRange: NSRange)
 func setMarkedText(_ text: NSAttributedString, selectionRange: NSRange, replacementRange: NSRange)
}
protocol IMKUnicodeTextInput {}
enum NSUnderlineStyle: Int { case single = 1, thick = 2 }
extension NSAttributedString.Key { static let underlineStyle = Self("underline") }
let debugLogging=false, debugInputController=false, debugInputReceiver=false
func dlog(_ enabled: Bool, _ format: String, _ values: Any...) {}
final class HanjaIMEComposer {
 let session: HanjaIMESession
 init(_ session: HanjaIMESession) { self.session=session }
 var composedString: String { session.displayString }
}
final class Composer {
 func synchronizeSelectedMode(_ mode: String?) { precondition(delegate is HanjaIMEComposer) }
 var delegate: AnyObject
 init(_ value: HanjaIMEComposer) { delegate=value }
 func cancelComposition() { (delegate as! HanjaIMEComposer).session.commitCurrent() }
 func dequeueCommitString() -> String { (delegate as! HanjaIMEComposer).session.takeCommit() }
}
final class InputMethodServer {
 static let shared=InputMethodServer()
 func showOrHideCandidates(controller: NSObject) {}
}
final class Document: NSObject, IMKTextInput, IMKUnicodeTextInput {
 var text="앞 😀 "
 var marked=NSRange(location: NSNotFound,length: 0)
 var selection=NSRange(location: 5,length: 0)
 var inserts=0
 func markedRange() -> NSRange { marked }
 func range(_ value: NSRange) -> NSRange {
  value.location != NSNotFound ? value : (marked.location != NSNotFound ? marked : selection)
 }
 func insertText(_ value: String, replacementRange: NSRange) {
  let target=range(replacementRange)
  text=(text as NSString).replacingCharacters(in: target,with: value)
  selection=NSRange(location: target.location+value.utf16.count,length: 0)
  marked=NSRange(location: NSNotFound,length: 0)
  inserts+=1
 }
 func setMarkedText(_ value: NSAttributedString, selectionRange: NSRange, replacementRange: NSRange) {
  precondition(selectionRange.location+selectionRange.length <= value.length)
  let target=range(replacementRange)
  text=(text as NSString).replacingCharacters(in: target,with: value.string)
  marked=value.length > 0 ? NSRange(location: target.location,length: value.length) : NSRange(location: NSNotFound,length: 0)
  selection=NSRange(location: target.location+selectionRange.location,length: selectionRange.length)
 }
}
final class Receiver {
 let inputClient: IMKTextInput & IMKUnicodeTextInput
 let composer: Composer
 let controller=NSObject()
 var inputting=true
 init(_ doc: Document,_ value: HanjaIMEComposer) { inputClient=doc; composer=Composer(value) }
'''
tests=r'''
@main struct ClientBridgeTests {
 static var checks=0
 static func expect(_ ok: @autoclosure () -> Bool,_ message: String) {
  checks+=1
  if !ok() { fatalError(message) }
 }
 static func main() {
  let domain="org.hanjaime.bridge."+UUID().uuidString
  let defaults=UserDefaults(suiteName: domain)!
  defer { defaults.removePersistentDomain(forName: domain) }
  let usage=HanjaIMEUsageStore(defaults: defaults)
  let dictionary=RealDictionary(path: CommandLine.arguments[1])
  for keys in ["r","rk","gks","durtk","dkssudgktpdy"] {
   let hangul=RealHangulBuffer()
   let session=HanjaIMESession(hangul: hangul,usage: usage,lookup: dictionary.lookup)
   let doc=Document(), receiver: Receiver
   receiver=Receiver(doc,HanjaIMEComposer(session))
   for key in keys {
    _=session.handle(.text) { hangul.feed(key) }
    _=receiver.updateHanjaIMEComposition()
    expect(doc.text == "앞 😀 "+session.reading,"all syllables rendered")
    expect(doc.selection.length == 0 && doc.selection.location == doc.text.utf16.count,"caret, no blue selection")
   }
   let raw=session.reading
   doc.selection=NSRange(location: doc.text.utf16.count-1,length: 1)
   _=session.handle(.enter)
   _=receiver.commitCompositionEvent(doc)
   _=receiver.updateHanjaIMEComposition()
   expect(doc.text == "앞 😀 "+raw,"replace whole marked range")
   expect(doc.marked.location == NSNotFound && doc.inserts == 1,"unmarked, committed once")
   receiver.inputting=false
   _=receiver.commitCompositionEvent(doc)
   _=receiver.updateHanjaIMEComposition()
   expect(doc.text == "앞 😀 "+raw && doc.inserts == 1,"late update cannot delete final syllable")
   doc.insertText("\n",replacementRange: NSRange(location: NSNotFound,length: 0))
   expect(doc.text == "앞 😀 "+raw+"\n","newline follows complete word")
  }
  let hangul=RealHangulBuffer()
  let session=HanjaIMESession(hangul: hangul,usage: usage,lookup: dictionary.lookup)
  let doc=Document(), receiver: Receiver
  receiver=Receiver(doc,HanjaIMEComposer(session))
  for key in "rhdiddl" { _=session.handle(.text) { hangul.feed(key) } }
  session.highlight(index: session.candidates.firstIndex { $0.value == "🐈" }!,generation: session.generation)
  _=receiver.updateHanjaIMEComposition()
  expect(doc.text == "앞 😀 🐈" && doc.selection.location == 7,"UTF-16 emoji caret")
  receiver.inputting=false
  _=receiver.commitCompositionEvent(doc)
  _=receiver.updateHanjaIMEComposition()
  expect(doc.text == "앞 😀 🐈" && doc.inserts == 1,"focus commits emoji once")
  for key in "rk" { _=session.handle(.text) { hangul.feed(key) }; _=receiver.updateHanjaIMEComposition() }
  for _ in 0..<2 { _=session.handle(.backspace) { hangul.backspace() }; _=receiver.updateHanjaIMEComposition() }
  expect(doc.text == "앞 😀 🐈","empty composition preserves previous emoji")
  usage.flush()
  print("PASS: \(checks) client-bridge checks; production commit/render methods + UTF-16 model, not AppKit")
 }
}
'''
out=ROOT/'build/client-bridge-tests'; out.mkdir(parents=True,exist_ok=True)
helpers=(ROOT/'tests/CoreTests.swift').read_text().split('@main struct CoreTests')[0]
f=out/'ClientBridge.swift'
f.write_text(prefix+'\n'.join(method(n) for n in ['commitCompositionEvent','cancelCompositionEvent','updateHanjaIMEComposition'])+'\n}\n'+helpers+tests)
native=ROOT/'build/portable-tests/libhangul/hangul'
headers=sorted((a.swiftc.parent.parent/'lib/clang').glob('*/include/stddef.h'))
cmd=[a.swiftc,'-swift-version','5','-I',ROOT/'build/portable-tests/CHangul','-Xcc','-I'+str(headers[-1].parent),'-L',native,'-lhangul','-Xlinker','-rpath','-Xlinker',native,ROOT/'Sources/HanjaIMEStorage.swift',ROOT/'Sources/HanjaIMECore.swift',f,'-o',out/'client-tests']
subprocess.run(list(map(str,cmd)),check=True)
subprocess.run([str(out/'client-tests'),str(a.source/'OSXCore/data/hanja/hanjaw.txt')],check=True)
