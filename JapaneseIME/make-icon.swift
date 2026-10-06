import AppKit
let folder=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func draw(_ size:Int)->Data {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus();let s=CGFloat(size)/1024;NSGraphicsContext.current!.cgContext.scaleBy(x:s,y:s)
 let shape=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200)
 NSColor(calibratedWhite:0.92,alpha:1).setFill();shape.fill()
 NSColor(calibratedWhite:0.45,alpha:1).setStroke();shape.lineWidth=20;shape.stroke()
 let style=NSMutableParagraphStyle();style.alignment = .center
 let text=NSAttributedString(string:"日",attributes:[.font:NSFont(name:"HiraginoSans-W5",size:500) ?? .systemFont(ofSize:500),.foregroundColor:NSColor(calibratedWhite:0.12,alpha:1)])
 let extent=text.size();text.draw(at:NSPoint(x:(1024-extent.width)/2,y:(1024-extent.height)/2))
 image.unlockFocus();return NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
}
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {try draw(size).write(to:folder.appendingPathComponent(name+".png"))}
