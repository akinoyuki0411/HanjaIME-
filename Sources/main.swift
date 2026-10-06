//
//  main.swift
//  Gureum
//
//  Created by Jeong YunWon on 2018. 9. 26..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Cocoa

// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

let mainNibName = Bundle.main.infoDictionary!["NSMainNibFile"] as! String
let nib = NSNib(nibNamed: NSNib.Name(mainNibName), bundle: Bundle.main)!
// Keep the nib delegate alive: NSApplication.delegate is a weak reference.
var mainNibObjects: NSArray?
if nib.instantiate(withOwner: NSApplication.shared, topLevelObjects: &mainNibObjects) == false {
  dlog(true, "!! Gureum fails to load Main Nib File !!")
}

if let delegate = mainNibObjects?.compactMap({ $0 as? GureumAppDelegate }).first {
  NSApplication.shared.delegate = delegate
}

if CommandLine.arguments.contains("--settings") {
  NSApplication.shared.setActivationPolicy(.regular)
  DispatchQueue.main.async {
    preferencesWindow.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}

dlog(true, "****   Main bundle \(mainNibName) loaded   ****")
NSApplication.shared.run()
dlog(true, "******* Gureum finalized! *******")
