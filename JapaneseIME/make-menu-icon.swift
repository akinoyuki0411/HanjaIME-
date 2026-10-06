import AppKit
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
let image=NSImage(size:NSSize(width:22,height:18))
for scale in [1,2] {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:22*scale,pixelsHigh:18*scale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 rep.size=NSSize(width:22,height:18)
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 NSGraphicsContext.current!.cgContext.scaleBy(x:CGFloat(scale),y:CGFloat(scale))
 NSColor(calibratedWhite:0.93,alpha:1).setFill();NSColor(calibratedWhite:0.45,alpha:1).setStroke()
 let shape=NSBezierPath(roundedRect:NSRect(x:1,y:2,width:20,height:14),xRadius:4,yRadius:4);shape.lineWidth=0.5;shape.fill();shape.stroke()
 let style=NSMutableParagraphStyle();style.alignment = .center
 let text=NSAttributedString(string:"日",attributes:[.font:NSFont(name:"HiraginoSans-W5",size:10) ?? .systemFont(ofSize:10),.foregroundColor:NSColor(calibratedWhite:0.12,alpha:1)])
 let extent=text.size();text.draw(at:NSPoint(x:(22-extent.width)/2,y:(18-extent.height)/2))
 NSGraphicsContext.restoreGraphicsState();image.addRepresentation(rep)
 if scale==1 {try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("JapaneseMenuSmall.png"))}
 try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(scale==1 ? "JapaneseMenu.png" : "JapaneseMenu@2x.png"))
}
try image.tiffRepresentation!.write(to:folder.appendingPathComponent("JapaneseMenu.tiff"))
