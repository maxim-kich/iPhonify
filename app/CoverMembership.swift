import AppKit

// Experimental own-window membership only. No system/third-party windows.
enum CoverMembership {
 static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)
 static func function<T>(_ name:String,_ type:T.Type) -> T? {
  guard let handle,let address = dlsym(handle,name) else { return nil }
  return unsafeBitCast(address,to:type)
 }
 static var connection:Int32? {
  function("SLSMainConnectionID",(@convention(c) () -> Int32).self)?()
 }
 static func ids(_ window:NSWindow) -> [UInt64] {
  guard let c = connection,
        let copy = function("SLSCopySpacesForWindows",(@convention(c) (Int32,Int32,CFArray) -> Unmanaged<CFArray>?).self) else { return [] }
  return (copy(c,7,[NSNumber(value:window.windowNumber)] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value)
 }
 static func routeIDs(from source:UInt64,to destination:UInt64) -> [UInt64]? {
  guard let c = connection,
        let managed = function("SLSCopyManagedDisplaySpaces",(@convention(c) (Int32) -> Unmanaged<CFArray>?).self),
        let displays = managed(c)?.takeRetainedValue() as? [[String:Any]] else { return nil }
  for display in displays {
   let spaces = (display["Spaces"] as? [[String:Any]] ?? []).compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
   if let a = spaces.firstIndex(of:source), let b = spaces.firstIndex(of:destination) {
    return Array(spaces[min(a,b)...max(a,b)])
   }
  }
  return nil
 }
 static func assign(_ window:NSWindow,to target:UInt64) -> Bool {
  guard let c = connection,
        let add = function("SLSAddWindowsToSpaces",(@convention(c) (Int32,CFArray,CFArray) -> Void).self),
        let remove = function("SLSRemoveWindowsFromSpaces",(@convention(c) (Int32,CFArray,CFArray) -> Void).self) else { return false }
  let windows = [NSNumber(value:window.windowNumber)] as CFArray
  add(c,windows,[NSNumber(value:target)] as CFArray)
  let other = ids(window).filter { $0 != target }.map { NSNumber(value:$0) }
  if !other.isEmpty { remove(c,windows,other as CFArray) }
  return ids(window) == [target]
 }
}
