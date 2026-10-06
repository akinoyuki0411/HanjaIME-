import AppKit
import InputMethodKit
@main struct NativeTests {
 static func main() {
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let delegate=JapaneseAppDelegate();app.delegate=delegate
  let client=MockInputClient(frame:NSRect(x:0,y:0,width:400,height:200))
  let controller=JapaneseInputController()
  controller.activateServer(client)
  for letter in "gakkou" {precondition(controller.inputText(String(letter),key:0,modifiers:0,client:client))}
  precondition(client.string=="がっこう",client.string)
  precondition(controller.inputText(" ",key:49,modifiers:0,client:client))
  precondition(client.string=="學校",client.string)
  precondition(controller.inputText("\n",key:36,modifiers:0,client:client))
  precondition(client.string=="學校" && !client.hasMarkedText())
  for letter in "tenki" {_ = controller.inputText(String(letter),key:0,modifiers:0,client:client)}
  controller.deactivateServer(client)
  precondition(client.string=="學校てんき" && !client.hasMarkedText(),client.string)
  precondition(!controller.inputText("a",key:0,modifiers:0,client:client),"Inactive context consumed input")
  controller.activateServer(client)
  for letter in "nihon" {_ = controller.inputText(String(letter),key:0,modifiers:0,client:client)}
  _ = controller.inputText("",key:98,modifiers:0,client:client)
  precondition(client.string=="學校てんきニホン",client.string)
  controller.deactivateServer(client)
  client.string="";controller.activateServer(client)
  for letter in "gakkou" {_ = controller.inputText(String(letter),key:0,modifiers:0,client:client)}
  let panel=controller.candidatePanelForTesting!
  if CommandLine.arguments.contains("--render") {
   let view=panel.contentView!
   let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
   view.cacheDisplay(in:view.bounds,to:rep)
   try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/japanese-candidates.png"))
  }
  precondition(panel.frame.width <= 260,"Candidate panel too wide")
  let books=panel.contentView!.subviews.flatMap{$0.subviews}.compactMap{$0 as? JapaneseCandidateButton}.filter{$0.image != nil}
  precondition(!books.isEmpty,"Missing dictionary buttons")
  let beforeHover=client.string
  (books.first as? JapaneseBookButton)?.hover?()
  RunLoop.current.run(until:Date().addingTimeInterval(0.4))
  precondition(controller.definitionPanelForTesting?.isVisible==true,"Hover did not open definition")
  precondition(client.string==beforeHover,"Hover committed input")
  precondition(controller.definitionPanelForTesting!.frame.width==280 && controller.definitionPanelForTesting!.frame.height==220,"Definition popup too large")
  if CommandLine.arguments.contains("--naver-live") {
    RunLoop.current.run(until:Date().addingTimeInterval(14))
    let view=controller.definitionPanelForTesting!.contentView!
    let text=view.subviews.compactMap{$0 as? NSScrollView}.first!.documentView as! NSTextView
    precondition(text.string.contains("학교"),"Live NAVER meaning unavailable: "+text.string)
    print("Live compact NAVER definition: ",text.string)
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/japanese-compact-definition.png"))
    let korean=JapaneseNaverDefinitionView(url:URL(string:"https://hanja.dict.naver.com/#/search?query=%E4%BA%8C")!);korean.start()
    RunLoop.current.run(until:Date().addingTimeInterval(14))
    let koreanText=korean.subviews.compactMap{$0 as? NSScrollView}.first!.documentView as! NSTextView
    precondition(koreanText.string.contains("두"),"Korean compact meaning unavailable: "+koreanText.string)
    print("Live Korean compact lookup passed")
    korean.stop()
  }
  let size=panel.frame.size
  let tabs=panel.contentView!.subviews.compactMap{$0 as? NSSegmentedControl}.first!
  precondition(tabs.segmentCount==5)
  tabs.selectedSegment=2;_ = (tabs.target as? NSObject)?.perform(tabs.action!,with:tabs)
  precondition(panel.frame.size==size,"Category filtering resized panel")
  let candidate=panel.contentView!.subviews.flatMap{$0.subviews}.compactMap{$0 as? JapaneseCandidateButton}.first!
  precondition(candidate.title.contains("学校"),candidate.title)
  _ = (candidate.target as? NSObject)?.perform(candidate.action!,with:candidate)
  precondition(client.string=="学校",client.string)
  controller.deactivateServer(client)
  client.string="";controller.activateServer(client)
  for letter in "hoshi" {_ = controller.inputText(String(letter),key:0,modifiers:0,client:client)}
  let symbolTabs=controller.candidatePanelForTesting!.contentView!.subviews.compactMap{$0 as? NSSegmentedControl}.first!
  symbolTabs.selectedSegment=4;_ = (symbolTabs.target as? NSObject)?.perform(symbolTabs.action!,with:symbolTabs)
  let symbols=controller.candidatePanelForTesting!.contentView!.subviews.flatMap{$0.subviews}.compactMap{$0 as? JapaneseCandidateButton}
  precondition(symbols.contains{$0.title.contains("★")},"Symbols filter empty")
  precondition(!symbols.contains{$0.image != nil},"Symbols show dictionary buttons")
  let star=symbols.first{$0.title.contains("★")}!;_ = (star.target as? NSObject)?.perform(star.action!,with:star)
  precondition(client.string=="★","Symbol selection did not commit")
  controller.deactivateServer(client)
  print("Japanese native controller: kana, old-form conversion, commit, context switch, inactive input and F7 passed.")
 }
}
