import AppKit

// Full-screen handoffs hide Finder while it is still off-Space. Ordinary
// desktop handoffs use its existing windows, because Finder can immediately
// unhide itself when the last regular desktop app is hidden.
enum FinderDismissal {
 struct Preparation {
  var hidden:[NSRunningApplication] = []
  var windows:[AXUIElement] = []
 }
 static func prepare(hideApplication:Bool) -> Preparation {
  guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first else { return Preparation() }
  if hideApplication {
   guard !finder.isHidden else { return Preparation() }
   let app = AXUIElementCreateApplication(finder.processIdentifier)
   AXUIElementSetMessagingTimeout(app,0.1)
   if AXUIElementSetAttributeValue(app,kAXHiddenAttribute as CFString,kCFBooleanTrue) == .success {
    return Preparation(hidden:[finder])
   }
   return Preparation()
  }
  return Preparation(windows:AccessoryDismissal.minimize(finder,hideApplication:false))
 }
 static func settle(spaceID:UInt64,restoreVisibility:Bool,protectSource:Bool) -> [AXUIElement] {
  guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first else { return [] }
  guard !protectSource else { return AccessoryDismissal.minimize(finder,hideApplication:false) }
  let app = AXUIElementCreateApplication(finder.processIdentifier)
  AXUIElementSetMessagingTimeout(app,0.1)
  var minimized:[AXUIElement] = []
  if finder.isHidden,
     let library = dlopen(nil,RTLD_LAZY), let symbol = dlsym(library,"_AXUIElementGetWindow"),
     let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY),
     let main = dlsym(sky,"SLSMainConnectionID"), let copy = dlsym(sky,"SLSCopySpacesForWindows") {
   typealias Getter = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> AXError
   typealias Connection = @convention(c) () -> Int32
   typealias Membership = @convention(c) (Int32,Int32,CFArray) -> Unmanaged<CFArray>?
   let getID = unsafeBitCast(symbol,to:Getter.self), connection = unsafeBitCast(main,to:Connection.self)()
   let spaces = unsafeBitCast(copy,to:Membership.self)
   var value:CFTypeRef?
   if AXUIElementCopyAttributeValue(app,kAXWindowsAttribute as CFString,&value) == .success,
      let windows = value as? [AXUIElement] {
    for window in windows {
     var id:CGWindowID = 0, role:CFTypeRef?, mini:CFTypeRef?
     guard getID(window,&id) == .success, id != 0,
           AXUIElementCopyAttributeValue(window,kAXRoleAttribute as CFString,&role) == .success,
           role as? String == kAXWindowRole,
           AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute as CFString,&mini) == .success,
           mini as? Bool == false,
           let ids = spaces(connection,7,[NSNumber(value:id)] as CFArray)?.takeRetainedValue() as? [NSNumber],
           ids.contains(where: { $0.uint64Value == spaceID }),
           AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanTrue) == .success else { continue }
     minimized.append(window)
    }
   }
  }
  if restoreVisibility { _ = AXUIElementSetAttributeValue(app,kAXHiddenAttribute as CFString,kCFBooleanFalse) }
  // A conservative visible-window fallback if this OS/app omits hidden windows.
  minimized += AccessoryDismissal.minimize(finder,hideApplication:false)
  return minimized
 }
 // Finder may acknowledge unminimize while off-Space without applying it.
 // Restore its window state while the desktop is still current and the app is
 // hidden; defer app visibility until the source Space is settled.
 static func prepareReturn(_ windows:[AXUIElement],protectSource:Bool) -> (windows:[AXUIElement],unhide:[NSRunningApplication],verified:Bool) {
  guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first else { return ([],[],true) }
  let owned = windows.filter { window in var pid:pid_t = 0; return AXUIElementGetPid(window,&pid) == .success && pid == finder.processIdentifier }
  guard !owned.isEmpty else { return ([],[],true) }
  let app = AXUIElementCreateApplication(finder.processIdentifier)
  AXUIElementSetMessagingTimeout(app,0.1)
  let conceal = !protectSource && !finder.isHidden
  if conceal, AXUIElementSetAttributeValue(app,kAXHiddenAttribute as CFString,kCFBooleanTrue) != .success { return ([],[],false) }
  AccessoryDismissal.restore(owned)
  if !protectSource {
   // An unminimized window in a hidden app may remain ordered out. Repair its
   // ordering while Finder is visible on its own desktop, still covered by
   // our full-size return surface, then conceal Finder for the Space switch.
   _ = AXUIElementSetAttributeValue(app,kAXHiddenAttribute as CFString,kCFBooleanFalse)
   for window in owned { _ = AXUIElementPerformAction(window,kAXRaiseAction as CFString) }
   _ = AXUIElementSetAttributeValue(app,kAXHiddenAttribute as CFString,kCFBooleanTrue)
  }
  var pending = owned
  for _ in 0..<6 {
   pending = pending.filter { window in
    var value:CFTypeRef?
    return AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute as CFString,&value) != .success || value as? Bool != false
   }
   if pending.isEmpty { break }
   Thread.sleep(forTimeInterval:0.03)
  }
  let restored = owned.filter { window in !pending.contains { CFEqual(window,$0) } }
  log("Finder return state restored=\(restored.count)/\(owned.count)")
  return (restored,conceal ? [finder] : [],pending.isEmpty)
 }
}
