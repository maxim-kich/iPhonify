import AppKit
import ScreenCaptureKit

enum WindowSurfaceProbe {
 static func exists(id:CGWindowID) -> Bool {
  let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow,id) as? [[String:Any]] ?? []
  return windows.contains { ($0[kCGWindowNumber as String] as? UInt32) == id }
 }
 static func focusedID(pid:pid_t) -> CGWindowID? {
  let app = AXUIElementCreateApplication(pid)
  AXUIElementSetMessagingTimeout(app,0.06)
  var value:CFTypeRef?
  guard AXUIElementCopyAttributeValue(app,kAXFocusedWindowAttribute as CFString,&value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
        let library = dlopen(nil,RTLD_LAZY), let symbol = dlsym(library,"_AXUIElementGetWindow") else { return nil }
  typealias Getter = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> AXError
  var id:CGWindowID = 0
  return unsafeBitCast(symbol,to:Getter.self)(value as! AXUIElement,&id) == .success && id != 0 ? id : nil
 }
 private static func capture(_ filter:SCContentFilter) async -> Bool {
  let configuration = SCStreamConfiguration()
  configuration.width = 96; configuration.height = 64; configuration.showsCursor = false
  do {
   let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
   // Capture success is stronger than Space/window-list bookkeeping. It is
   // not proof that the physical display presented every animation frame.
   return image.width > 0 && image.height > 0 && image.dataProvider != nil
  } catch { log("Surface capture unavailable: \(error.localizedDescription)"); return false }
 }
 static func window(id:CGWindowID) async -> Bool {
  do {
   let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
   guard let window = content.windows.first(where: { $0.windowID == id && $0.isOnScreen }) else { return false }
   return await capture(SCContentFilter(desktopIndependentWindow:window))
  } catch { return false }
 }
 static func desktop(displayName:String) async -> Bool {
  do {
   let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
   guard let display = content.displays.first(where: {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID($0.displayID)?.takeRetainedValue() else { return false }
    return CFUUIDCreateString(nil,uuid) as String == displayName
   }) else { return false }
   let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
   return await capture(SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[]))
  } catch { return false }
 }
}
