import AppKit
let folder=URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func draw(_ size:Int)->Data {
 let image=NSImage(size:NSSize(width:size,height:size)); image.lockFocus(); let s=CGFloat(size)/1024
 NSGraphicsContext.current!.cgContext.scaleBy(x:s,y:s)
 let base=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200)
 let gradient=NSGradient(starting:NSColor(calibratedRed:0.06,green:0.23,blue:0.44,alpha:1),ending:NSColor(calibratedRed:0.12,green:0.64,blue:0.64,alpha:1))!
 gradient.draw(in:base,angle:55)
 NSColor.white.withAlphaComponent(0.94).setFill()
 NSBezierPath(roundedRect:NSRect(x:244,y:575,width:536,height:205),xRadius:44,yRadius:44).fill()
 NSColor(calibratedRed:0.08,green:0.32,blue:0.48,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:416,y:733,width:192,height:47),xRadius:19,yRadius:19).fill()
 NSColor.white.withAlphaComponent(0.94).setFill()
 NSBezierPath(roundedRect:NSRect(x:244,y:244,width:536,height:230),xRadius:44,yRadius:44).fill()
 NSColor(calibratedRed:0.08,green:0.32,blue:0.48,alpha:1).setFill()
 for row in 0..<2 {for col in 0..<6 { NSBezierPath(roundedRect:NSRect(x:286+col*78,y:355+row*56,width:57,height:34),xRadius:9,yRadius:9).fill() }}
 NSBezierPath(roundedRect:NSRect(x:397,y:288,width:230,height:31),xRadius:10,yRadius:10).fill()
 NSColor.white.withAlphaComponent(0.6).setStroke(); let line=NSBezierPath();line.move(to:NSPoint(x:512,y:492));line.line(to:NSPoint(x:512,y:557));line.lineWidth=12;line.stroke()
 image.unlockFocus(); let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!; return rep.representation(using:.png,properties:[:])!
}
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {try draw(size).write(to:folder.appendingPathComponent(name+".png"))}
