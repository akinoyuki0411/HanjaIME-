import AppKit
import WebKit

final class JapaneseNaverDefinitionView: NSView, WKNavigationDelegate {
    private static let cache:NSCache<NSString,NSString> = {let cache=NSCache<NSString,NSString>();cache.countLimit=64;return cache}()
    var onDefinition:((String)->Void)?
    private let title=NSTextField(labelWithString:"네이버 사전 · NAVER")
    private var open:NSButton!
    private let url:URL
    private let web:WKWebView
    private let body=NSTextView()
    private var retry:DispatchWorkItem?
    private var stopped=false
    private var extracting=false
    private var attempts=0
    init(url:URL) {
        self.url=url
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        web=WKWebView(frame:NSRect(x:0,y:0,width:640,height:600),configuration:config)
        super.init(frame:NSRect(x:0,y:0,width:280,height:220))
        wantsLayer=true;layer?.cornerRadius=7;layer?.masksToBounds=true;layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        title.font = .systemFont(ofSize:11);title.textColor = .secondaryLabelColor
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        body.frame=NSRect(x:0,y:0,width:260,height:160);body.autoresizingMask=[.width];body.isEditable=false;body.isSelectable=true;body.drawsBackground=false;body.font = .systemFont(ofSize:12);body.textColor = .labelColor;body.isVerticallyResizable=true;body.isHorizontallyResizable=false;body.textContainer?.widthTracksTextView=true;body.textContainerInset=NSSize(width:2,height:3)
        body.string="뜻을 찾는 중…";scroll.documentView=body
        open=NSButton(title:"네이버에서 자세히 보기",target:self,action:#selector(openBrowser));open.bezelStyle = .rounded;open.controlSize = .small
        for child in [title,scroll,open!] {child.translatesAutoresizingMaskIntoConstraints=false;addSubview(child)}
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),title.topAnchor.constraint(equalTo:topAnchor,constant:8),title.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-10),title.heightAnchor.constraint(equalToConstant:18),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-8),scroll.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),scroll.bottomAnchor.constraint(equalTo:open.topAnchor,constant:-5),open.centerXAnchor.constraint(equalTo:centerXAnchor),open.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-7)])
        web.isHidden=true;addSubview(web);web.navigationDelegate=self
    }
    required init?(coder:NSCoder) {fatalError("Use init")}
    func showText(_ text:String,provider:String) {body.string=text;title.stringValue=provider;open.isHidden=provider=="Apple"}
    func start() {
        title.stringValue=JL("네이버 사전 · NAVER","NAVER Dictionary","NAVER辞書");open.isHidden=false
        if let cached=Self.cache.object(forKey:url.absoluteString as NSString) {body.string=cached as String;onDefinition?(cached as String);return}
        web.load(URLRequest(url:url,timeoutInterval:12))
        let work=DispatchWorkItem { [weak self] in self?.extract() };retry=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    func stop() {stopped=true;retry?.cancel();web.stopLoading();web.navigationDelegate=nil}
    @objc private func openBrowser() {NSWorkspace.shared.open(url)}
    private func extract() {
        guard !stopped,!extracting else{return};extracting=true;attempts += 1
        let script="""
        (() => {
          const query=new URLSearchParams(location.hash.split('?')[1]||'').get('query')||'';
          const letter=location.hostname==='hanja.dict.naver.com' && Array.from(query).length===1 ? document.querySelector('#searchPage_letter .row') : null;
          const row=letter || document.querySelector('#searchPage_entry .row') || document.querySelector('#searchPage_hanja .row') || document.querySelector('#searchPage_word .row');
          if(!row) return null;
          const clean=s=>(s||'').replace(/\\s+/g,' ').trim();
          const origin=row.querySelector('.origin .link');
          const kanji=row.querySelector('.origin ._kanji');
          const meaning=row.querySelector('.mean_list') || row.querySelector('.entry_mean');
          const source=row.querySelector('.source');
          if(!meaning || !clean(meaning.innerText)) return null;
          return [(clean(origin?.innerText)||query)+' '+clean(kanji?.innerText),clean(meaning.innerText).slice(0,600),clean(source?.innerText)].filter(Boolean).join('\\n\\n');
        })()
        """
        web.evaluateJavaScript(script) { [weak self] value,error in
            guard let self,!self.stopped else{return};self.extracting=false
            if let text=value as? String,!text.isEmpty {
                self.body.string=text;self.onDefinition?(text);Self.cache.setObject(text as NSString,forKey:self.url.absoluteString as NSString);self.retry?.cancel();self.stopped=true;self.web.stopLoading();return
            }
            if self.attempts>=24 {self.body.string="뜻풀이를 불러오지 못했습니다. 아래 버튼으로 네이버 사전에서 확인해 주세요.";self.web.stopLoading();return}
            let work=DispatchWorkItem { [weak self] in self?.extract() };self.retry=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
        }
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {extract()}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        guard !stopped,(error as NSError).code != NSURLErrorCancelled else{return};body.string="네이버 연결이 지연됩니다. 아래 버튼으로 직접 확인해 주세요."
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url,url.scheme=="https",let host=url.host,host=="dict.naver.com" || host.hasSuffix(".dict.naver.com") else {decisionHandler(.cancel);return};decisionHandler(.allow)
    }
}
