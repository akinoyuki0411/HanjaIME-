import AppKit
import InputMethodKit
import SwiftUI
import CoreServices
import QuartzCore

final class JapaneseAppDelegate:NSObject,NSApplicationDelegate {
    var server:IMKServer?
    var settings:NSWindow?
    var changelog:NSWindow?
    lazy var dictionary:JapaneseDictionary? = {
        guard let url=Bundle.main.resourceURL else{return nil}
        return try? JapaneseDictionary(dictionary:url.appendingPathComponent("SKK-JISYO.L.utf8"),oldMap:url.appendingPathComponent("OldForms.json"))
    }()
    func applicationDidFinishLaunching(_ notification:Notification) {
        if CommandLine.arguments.contains("--settings") {openSettings();return}
        _ = dictionary
        server=IMKServer(name:Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "org.hanjaime.inputmethod.Japanese_Connection",bundleIdentifier:Bundle.main.bundleIdentifier)
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(openSettings),name:Notification.Name("org.hanjaime.japanese.openSettings"),object:nil)
    }
    @objc func openSettings() {
        if settings == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:490),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=JL("한지미 일본어 입력기 설정","HanjaIME Japanese Input Settings","HanjaIME 日本語 入力設定");window.minSize=NSSize(width:660,height:430);window.titlebarAppearsTransparent=true;window.contentView=NSHostingView(rootView:JapaneseSettings());window.isReleasedWhenClosed=false;window.center();settings=window
        }
        settings?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func resizeSettings() {
        guard let window=settings else{return}
        let screen=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let height=min(JapanesePreferences.shared.tab.height+28,screen.height)
        let old=window.frame;let width:CGFloat=660
        window.title=JL("한지미 일본어 입력기 설정","HanjaIME Japanese Input Settings","HanjaIME 日本語 入力設定")
        let frame=NSRect(x:max(screen.minX,min(old.midX-width/2,screen.maxX-width)),y:max(screen.minY,min(old.maxY-height,screen.maxY-height)),width:width,height:height)
        NSAnimationContext.runAnimationGroup {context in
            context.duration=window.isVisible ? 0.25 : 0
            context.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
            window.animator().setFrame(frame,display:true)
        }
    }
    @objc func openAbout() {JapanesePreferences.shared.tab = .about;openSettings()}
    @objc func checkUpdates() {NSWorkspace.shared.open(URL(string:"https://github.com/akinoyuki0411/HanjaIME-/releases")!)}
    @objc func openLink(_ sender:NSMenuItem) {if let value=sender.representedObject as? String,let url=URL(string:value) {NSWorkspace.shared.open(url)}}
    @objc func showChangelog() {
        if changelog == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:700),styleMask:[.titled,.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.title=JL("변경 내역","Changelog","変更履歴");window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.minSize=NSSize(width:620,height:480);window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:JapaneseChangelog());window.center();changelog=window
        }
        changelog?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {CommandLine.arguments.contains("--settings")}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {openSettings();return true}
}
class JapaneseCandidateButton:NSButton { var generation=0 }
final class JapaneseBookButton:JapaneseCandidateButton {
    var hover:(()->Void)?
    var leave:(()->Void)?
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking {removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(area);tracking=area;super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) {hover?()}
    override func mouseExited(with event:NSEvent) {leave?()}
}
final class JapaneseCandidateWindow:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}

@objc(HanjaIMEJapaneseController)
final class JapaneseInputController:IMKInputController {
    private var roman=KanaRomanizer()
    private var allRows:[JapaneseCandidate]=[]
    private var category=0
    private var rows:[JapaneseCandidate]=[]
    private var selected=0
    private var converting=false
    private var active=false
    private var host:IMKTextInput?
    private var caret=NSRect.zero
    private var panel:JapaneseCandidateWindow?
    private var generation=0
    private var definitionPanel:JapaneseCandidateWindow?
    private var hoverRequest=UUID()
    override init!(server:IMKServer,delegate:Any!,client inputClient:Any) {
        super.init(server:server,delegate:delegate,client:inputClient)
        host=inputClient as? IMKTextInput
    }
    #if JAPANESE_NATIVE_TEST
    override init() {super.init()}
    #endif
    override func recognizedEvents(_ sender:Any!)->Int {Int(NSEvent.EventTypeMask.keyDown.rawValue)}
    override func activateServer(_ sender:Any!) {
        #if !JAPANESE_NATIVE_TEST
        super.activateServer(sender)
        #endif
        active=true;bind(sender)
        host?.overrideKeyboard(withKeyboardNamed:"com.apple.keylayout.ABC")
    }
    override func deactivateServer(_ sender:Any!) {
        active=false;commit();panel?.orderOut(nil)
        #if !JAPANESE_NATIVE_TEST
        super.deactivateServer(sender)
        #endif
    }
    override func inputControllerWillClose() {active=false;hoverRequest=UUID();(definitionPanel?.contentView as? JapaneseNaverDefinitionView)?.stop();definitionPanel?.orderOut(nil);panel?.orderOut(nil);super.inputControllerWillClose()}
    private func bind(_ sender:Any?) {
        guard let next=sender as? IMKTextInput else{return}
        if let host, ObjectIdentifier(host as AnyObject) != ObjectIdentifier(next as AnyObject) {commit();roman.clear();rows=[];panel?.orderOut(nil)}
        host=next
    }
    override func handle(_ event:NSEvent,client sender:Any)->Bool {
        guard event.type == .keyDown else{return false}
        return process(key:Int(event.keyCode),text:event.charactersIgnoringModifiers ?? "",flags:event.modifierFlags,sender:sender)
    }
    override func inputText(_ string:String!,key keyCode:Int,modifiers flags:Int,client sender:Any)->Bool {
        process(key:keyCode,text:string ?? "",flags:NSEvent.ModifierFlags(rawValue:UInt(bitPattern:flags)),sender:sender)
    }
    private func process(key:Int,text:String,flags:NSEvent.ModifierFlags,sender:Any)->Bool {
        guard active else{return false}
        bind(sender)
        if !flags.intersection([.command,.control,.option]).isEmpty {commit();return false}
        switch key {
        case 49: // Space
            if roman.display.isEmpty {return false}
            if converting {selected=(selected+1)%max(rows.count,1)} else {roman.flush();refreshRows();converting=true;selected=0}
            update();return true
        case 36,76: if roman.display.isEmpty {return false};commit();return true
        case 53:
            if converting {converting=false;selected=0;update();return true}
            if roman.display.isEmpty{return false};roman.clear();rows=[];update();return true
        case 51:
            if converting {converting=false;update();return true}
            if roman.display.isEmpty{return false};roman.backspace();refreshRows();update();return true
        case 125,126:
            guard !rows.isEmpty,!roman.display.isEmpty else{return false}
            converting=true;selected=(selected+(key==125 ? 1 : rows.count-1))%rows.count;update();return true
        case 116,121:
            guard !rows.isEmpty,!roman.display.isEmpty else{return false}
            movePage(key==121 ? 1 : -1);return true
        case 98: // F7
            guard !roman.display.isEmpty else{return false};roman.flush();commit(text:roman.katakana());return true
        default: break
        }
        if converting, let number=Int(text), (1...9).contains(number) {
            let index=(selected/9)*9+number-1
            if rows.indices.contains(index) {selected=index;commit();return true}
        }
        if let character=text.lowercased().first,text.count==1,("a"..."z").contains(String(character)) || text=="'" || text=="-" {
            if converting {commit()}
            roman.append(character);refreshRows();update();return true
        }
        if text == "," || text == "." {commit();host?.insertText(text=="," ? "、" : "。",replacementRange:NSRange(location:NSNotFound,length:0));return true}
        commit();return false
    }
    private func refreshRows() {
        let app=NSApp.delegate as? JapaneseAppDelegate
        var complete=roman;complete.flush()
        allRows=app?.dictionary?.candidates(complete.display) ?? []
        applyCategory()
        selected=min(selected,max(rows.count-1,0));generation += 1
    }
    private func update() {
        hoverRequest=UUID();(definitionPanel?.contentView as? JapaneseNaverDefinitionView)?.stop();definitionPanel?.orderOut(nil)
        guard let host else{return}
        let value=converting && rows.indices.contains(selected) ? rows[selected].text : roman.display
        host.setMarkedText(value,selectionRange:NSRange(location:value.utf16.count,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        if value.isEmpty || (!converting && !JapanesePreferences.shared.automatic) || allRows.isEmpty {panel?.orderOut(nil);return}
        showRows()
    }
    private func commit(text:String?=nil) {
        roman.flush()
        let value=text ?? (converting && rows.indices.contains(selected) ? rows[selected].text : roman.display)
        if !value.isEmpty {host?.insertText(value,replacementRange:NSRange(location:NSNotFound,length:0))}
        definitionPanel?.orderOut(nil);roman.clear();allRows=[];rows=[];category=0;selected=0;converting=false;generation += 1;panel?.orderOut(nil)
    }
    override func commitComposition(_ sender:Any!) {commit()}
    override func composedString(_ sender:Any!)->Any! {roman.display}
    override func menu()->NSMenu! {
        let menu=NSMenu()
        func add(_ title:String,_ action:Selector) {let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=NSApp.delegate;menu.addItem(item)}
        add(JL("한지미 일본어 정보","About HanjaIME Japanese","HanjaIME 日本語について"),#selector(JapaneseAppDelegate.openAbout))
        add(JL("환경설정…","Settings…","環境設定…"),#selector(JapaneseAppDelegate.openSettings))
        add(JL("새 버전 확인…","Check for Updates…","アップデートを確認…"),#selector(JapaneseAppDelegate.checkUpdates))
        add(JL("변경 내역 보기…","See Changelog…","変更履歴を見る…"),#selector(JapaneseAppDelegate.showChangelog))
        menu.addItem(.separator())
        let links=NSMenuItem(title:JL("웹사이트와 문의","Website and Support","ウェブサイトとお問い合わせ"),action:nil,keyEquivalent:"")
        let submenu=NSMenu();for (title,url) in [(JL("웹사이트","Website","ウェブサイト"),"https://github.com/akinoyuki0411/HanjaIME-"),(JL("버그 알리기","Report a Bug","不具合を報告"),"https://github.com/akinoyuki0411/HanjaIME-/issues")] {let item=NSMenuItem(title:title,action:#selector(JapaneseAppDelegate.openLink(_:)),keyEquivalent:"");item.target=NSApp.delegate;item.representedObject=url;submenu.addItem(item)}
        links.submenu=submenu;menu.addItem(links);return menu
    }
    @objc private func choose(_ button:JapaneseCandidateButton) {
        guard active,button.generation==generation,rows.indices.contains(button.tag) else{return}
        selected=button.tag;converting=true;commit()
    }
    private func applyCategory() {
        rows=allRows.filter {row in
            switch category {case 1:return row.label=="旧字体" || row.label=="漢字";case 2:return row.label=="新字体" || row.label=="漢字";case 3:return row.label=="ひらがな" || row.label=="カタカナ";case 4:return row.label=="記号";default:return true}
        }
    }
    private func candidateLabel(_ label:String)->String {
        switch label {case "記号":return JL("기호","Symbols","記号");case "旧字体":return JL("구자체","Old form","旧字体");case "新字体":return JL("신자체","Modern form","新字体");case "漢字":return JL("한자","Kanji","漢字");case "ひらがな":return JL("히라가나","Hiragana","ひらがな");default:return JL("카타카나","Katakana","カタカナ")}
    }
    @objc private func categoryChanged(_ control:NSSegmentedControl) {
        guard active else{return};category=control.selectedSegment;applyCategory();selected=0;generation += 1
        if rows.isEmpty {converting=false};update()
    }
    @objc private func page(_ button:NSButton) {movePage(button.tag==0 ? -1 : 1)}
    private func movePage(_ direction:Int) {
        guard active,!rows.isEmpty else{return}
        let pages=(rows.count+8)/9;let page=(selected/9+direction+pages)%pages
        selected=page*9;converting=true;update()
    }
    #if JAPANESE_NATIVE_TEST
    var candidatePanelForTesting:NSPanel? {panel}
    var definitionPanelForTesting:NSPanel? {definitionPanel}
    #endif
    @objc private func showDefinition(_ button:JapaneseCandidateButton) {
        guard active,button.generation==generation,rows.indices.contains(button.tag),let panel else{return}
        let term=rows[button.tag].text
        let forms=(NSApp.delegate as? JapaneseAppDelegate)?.dictionary?.oldForms ?? [:]
        let modern=term.unicodeScalars.map {scalar -> String in
            if let match=forms.first(where:{$0.value.unicodeScalars.first?.value==scalar.value}),let value=UnicodeScalar(match.key) {return String(value)}
            return String(scalar)
        }.joined()
        var allowed=CharacterSet.urlQueryAllowed;allowed.remove(charactersIn:"&=+#?%")
        guard let query=modern.addingPercentEncoding(withAllowedCharacters:allowed),let url=URL(string:"https://ja.dict.naver.com/#/search?query="+query) else{return}
        let visible=panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let size=NSSize(width:min(280,visible.width),height:min(220,visible.height))
        let popup=JapaneseCandidateWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        popup.isReleasedWhenClosed=false;popup.hasShadow=true;popup.level = .popUpMenu
        let web=JapaneseNaverDefinitionView(url:url);web.frame=NSRect(origin:.zero,size:size);web.autoresizingMask=[.width,.height];popup.contentView=web
        (definitionPanel?.contentView as? JapaneseNaverDefinitionView)?.stop();definitionPanel?.orderOut(nil);definitionPanel=popup
        let x=panel.frame.maxX+5+size.width<=visible.maxX ? panel.frame.maxX+5 : max(visible.minX,panel.frame.minX-size.width-5)
        popup.setFrameOrigin(NSPoint(x:x,y:max(visible.minY,min(panel.frame.maxY-size.height,visible.maxY-size.height))));popup.orderFrontRegardless()
        let requestGeneration=generation
        let priority=JapanesePreferences.shared.dictionaryPriority
        web.onDefinition = { [weak self,weak popup] text in
            guard let self,let popup,self.active,self.generation==requestGeneration,self.definitionPanel===popup,JapanesePreferences.shared.appleTranslation else{return}
            if #available(macOS 15.0,*) {popup.contentView=NSHostingView(rootView:JapaneseTranslatedDefinition(text:text,url:priority == .naverFirst ? url : nil))}
        }
        let startNaver = {
            #if JAPANESE_NATIVE_TEST
            if CommandLine.arguments.contains("--naver-live") {web.start()}
            #else
            web.start()
            #endif
        }
        if priority == .naverFirst {startNaver();return}
        web.showText(JL("Apple 사전에서 찾는 중…","Looking up Apple Dictionary…","Apple辞書を検索中…"),provider:"Apple")
        DispatchQueue.global(qos:.userInitiated).async { [weak self,weak popup] in
            var result:String?
            for value in Array(Set([term,modern])) {
                if let definition=DCSCopyTextDefinition(nil,value as CFString,CFRange(location:0,length:value.utf16.count)) {let text=definition.takeRetainedValue() as String;if !text.isEmpty {result=text;break}}
            }
            DispatchQueue.main.async {
                guard let self,let popup,self.active,self.generation==requestGeneration,self.definitionPanel===popup else{return}
                if let result {web.showText(result,provider:"Apple");web.onDefinition?(result)}
                else if priority == .appleThenNaver {startNaver()}
                else {web.showText(JL("활성화된 Apple 사전에서 뜻을 찾지 못했습니다.","No definition in your enabled Apple dictionaries.","有効なApple辞書に意味が見つかりません。"),provider:"Apple")}
            }
        }
    }
    private func showRows() {
        guard active,let host else{return}
        if panel == nil {
            let window=JapaneseCandidateWindow(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isOpaque=false;window.backgroundColor = .clear;window.isFloatingPanel=true;window.isReleasedWhenClosed=false;window.level = .popUpMenu;window.hidesOnDeactivate=false;window.hasShadow=true;window.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary];panel=window
        }
        let start=selected/9*9;let end=min(start+9,rows.count)
        // Reserve the same rows across categories and pages, as in the Korean panel.
        let layoutRows=max(1,min(9,allRows.count));let textWidth=allRows.map { ($0.text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:14)]).width }.max() ?? 0
        let width:CGFloat=min(260,max(214,textWidth+80))
        let height=CGFloat(layoutRows)*26+44
        let content=NSVisualEffectView(frame:NSRect(x:0,y:0,width:width,height:height))
        content.material = .popover;content.blendingMode = .behindWindow;content.state = .active
        content.wantsLayer=true;content.layer?.cornerRadius=7;content.layer?.masksToBounds=true
        let header=NSTextField(labelWithString:roman.display);header.font = .systemFont(ofSize:10);header.textColor = .secondaryLabelColor;header.frame=NSRect(x:7,y:height-18,width:170,height:16);content.addSubview(header)
        let count=NSTextField(labelWithString:"\(rows.count)"+JL("개"," candidates","候補"));count.font = .systemFont(ofSize:10);count.textColor = .secondaryLabelColor;count.alignment = .right;count.frame=NSRect(x:width-125,y:height-18,width:70,height:16);content.addSubview(count)
        for (offset,title) in ["‹","›"].enumerated() {
            let button=NSButton(title:title,target:self,action:#selector(page(_:)))
            button.frame=NSRect(x:width-48+CGFloat(offset)*23,y:height-20,width:22,height:19);button.isBordered=false;button.tag=offset;button.isEnabled=rows.count>9
            button.toolTip=offset==0 ? JL("이전 후보 페이지","Previous page","前のページ") : JL("다음 후보 페이지","Next page","次のページ");content.addSubview(button)
        }
        for index in start..<end {
            let row=NSView(frame:NSRect(x:3,y:height-20-CGFloat(index-start+1)*26-1,width:width-6,height:25));row.wantsLayer=true;row.layer?.cornerRadius=5
            let isSelected=index==selected;row.layer?.backgroundColor=isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            let button=JapaneseCandidateButton(title:"\(index-start+1)  \(rows[index].text)",target:self,action:#selector(choose(_:)))
            button.tag=index;button.generation=generation;button.isBordered=false;button.alignment = .left;button.font = .systemFont(ofSize:14);button.frame=NSRect(x:3,y:1,width:width-44,height:23);button.cell?.lineBreakMode = .byTruncatingTail
            let detail=roman.display+" · "+candidateLabel(rows[index].label)
            let title=NSMutableAttributedString(string:button.title,attributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:isSelected ? NSColor.white : NSColor.labelColor])
            let titleWidth=(button.title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:14)]).width
            if titleWidth < width-100 {title.append(NSAttributedString(string:"  "+detail,attributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:isSelected ? NSColor.white : NSColor.secondaryLabelColor]))}
            button.attributedTitle=title;button.toolTip=rows[index].text+" — "+detail;row.addSubview(button)
            if ["漢字","旧字体","新字体"].contains(rows[index].label) {
                let book=JapaneseBookButton(title:"",target:self,action:#selector(showDefinition(_:)))
                book.tag=index;book.generation=generation;book.isBordered=false
                book.hover={ [weak self,weak book] in
                    guard let self else{return};let token=UUID();self.hoverRequest=token
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self,weak book] in guard let self,let book,self.hoverRequest==token else{return};self.showDefinition(book) }
                }
                book.leave={ [weak self] in
                    guard let self else{return};let leaveToken=UUID();self.hoverRequest=leaveToken
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { [weak self] in guard let self,self.hoverRequest==leaveToken,let popup=self.definitionPanel else{return};if !popup.frame.contains(NSEvent.mouseLocation) {popup.orderOut(nil)} }
                }
                book.image=NSImage(systemSymbolName:"book",accessibilityDescription:JL("뜻 보기","Definition","意味を見る"));book.contentTintColor=isSelected ? .white : .secondaryLabelColor
                book.frame=NSRect(x:width-34,y:2,width:23,height:21);book.toolTip=JL("네이버 일본어 사전에서 뜻 보기","Look up in Naver Japanese Dictionary","NAVER 日本語辞書で意味を見る")
                row.addSubview(book)
            }
            content.addSubview(row)
        }
        if rows.isEmpty {let empty=NSTextField(labelWithString:JL("이 분류에 해당하는 후보가 없습니다.","No candidates in this category.","この分類の候補はありません。"));empty.font = .systemFont(ofSize:11);empty.textColor = .secondaryLabelColor;empty.frame=NSRect(x:7,y:height-43,width:width-14,height:20);content.addSubview(empty)}
        let tabs=NSSegmentedControl(labels:[JL("표준","Standard","標準"),JL("한자","Kanji","漢字"),JL("신자체","Modern","新字体"),JL("가나","Kana","かな"),JL("기호","Symbols","記号")],trackingMode:.selectOne,target:self,action:#selector(categoryChanged(_:)))
        tabs.controlSize = .mini;tabs.font = .systemFont(ofSize:10);tabs.frame=NSRect(x:4,y:3,width:width-8,height:20);tabs.selectedSegment=category
        for index in 0..<5 {tabs.setWidth((width-10)/5,forSegment:index)}
        content.addSubview(tabs)
        panel?.contentView=content
        var rect=NSRect.zero;let range=host.selectedRange()
        if range.location != NSNotFound {_ = host.attributes(forCharacterIndex:range.location,lineHeightRectangle:&rect)}
        if rect.width.isFinite && rect.height.isFinite && (rect.origin != .zero) {caret=rect}
        let screen=NSScreen.screens.first(where:{$0.frame.contains(caret.origin)}) ?? NSScreen.main
        let visible=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1000,height:700)
        let anchor=caret == .zero ? NSPoint(x:visible.midX,y:visible.maxY-90) : NSPoint(x:caret.minX,y:caret.minY)
        let y=anchor.y-height-3 >= visible.minY ? anchor.y-height-3 : min(caret.maxY+3,visible.maxY-height)
        panel?.setFrame(NSRect(x:max(visible.minX,min(anchor.x,visible.maxX-width)),y:max(visible.minY,y),width:width,height:height),display:true)
        panel?.orderFrontRegardless()
    }
}
