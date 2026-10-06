import Foundation
@main struct PanelLayoutTests {
 static func main() {
  let screen=CGRect(x:0,y:0,width:1800,height:1169)
  let p=EnrollmentPanelLayout.calculate(screen:screen,safeTop:38,left:CGRect(x:0,y:1131,width:790,height:38),right:CGRect(x:1010,y:1131,width:790,height:38))
  precondition(p.frame.maxY==1169 && p.frame.midX==900 && p.topPadding==38)
  precondition(p.frame.width==340 && p.frame.height==446)
  let ext=EnrollmentPanelLayout.calculate(screen:CGRect(x:-1920,y:100,width:1920,height:1080),safeTop:0,left:nil,right:nil)
  precondition(ext.frame.midX == -960 && ext.frame.maxY==1172)
  precondition(ext.topPadding==12 && ext.frame.minX >= -1920)
  let small=EnrollmentPanelLayout.calculate(screen:CGRect(x:0,y:0,width:800,height:600),safeTop:0,left:nil,right:nil)
  precondition(small.frame.minY>=0 && small.frame.maxX<=800)
  print("PASS: 5 enrollment panel geometry checks (physical notch, external and smaller display)")
 }
}
