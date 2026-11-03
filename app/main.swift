// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import CoreImage
import QuartzCore
import TouchBridge

let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iPhonify.log")
func log(_ message: String) {
 let line = "\(Date()): \(message)\n"
 if let handle = try? FileHandle(forWritingTo: logURL) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close() }
 else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

struct Gesture {
 enum Action { case none, begin, update(Double), end(Bool, Double) }
 var origin: CGPoint?; var initial: [CGPoint] = []; var previous: CGPoint?; var previousTime = 0.0
 var firstContactTime: Double?; var startedAt = 0.0; var engaged = false
 var velocity = 0.0; var progress = 0.0; var rejected = false
 mutating func frame(_ points: [CGPoint], at time: Double) -> Action {
  guard points.count == 2 else {
   if engaged {
    let commit = points.count < 2 && (progress > 0.36 || (progress > 0.12 && velocity > 0.55))
    let v = velocity; self = Gesture(rejected:!points.isEmpty); return .end(commit,v)
   }
   if points.isEmpty { self = Gesture() }
   else if points.count != 1 || points[0].y > 0.065 { rejected = true }
   else if firstContactTime == nil { firstContactTime = time }
   if origin != nil { rejected = true; origin = nil }
   return .none
  }
  guard !rejected else { return .none }
  let sorted = points.sorted { $0.x < $1.x }
  let p = CGPoint(x:(sorted[0].x+sorted[1].x)/2,y:(sorted[0].y+sorted[1].y)/2)
  guard let o = origin else {
   guard points.allSatisfy({ $0.y <= 0.065 }), time-(firstContactTime ?? time) <= 0.12 else { rejected = true; return .none }
   origin = p; initial = sorted; previous = p; previousTime = time; startedAt = time
   return .none // Merely touching the edge must not claim a scroll.
  }
  let dy = p.y-o.y, dx = abs(p.x-o.x)
  let dt = time-previousTime
  if dt > 0 && dt < 0.15 { velocity = velocity*0.35+Double(p.y-(previous?.y ?? p.y))/dt*0.65 }
  previous = p; previousTime = time
  if !engaged {
   guard time-startedAt <= 0.28, dy >= -0.012, dx <= 0.025 else { rejected = true; return .none }
   guard dy >= 0.07 else { return .none }
   guard dx <= dy*0.4, zip(sorted,initial).allSatisfy({ $0.0.y-$0.1.y >= 0.055 }) else { rejected = true; return .none }
   engaged = true; return .begin
  }
  guard dx < 0.16, dy > 0.025 else { self = Gesture(rejected:true); return .end(false,0) }
  progress = max(0,Double(dy-0.07)/0.48)
  return .update(progress)
 }
}

enum GestureSource {
 static func permitsContext(spaceIsDesktop:Bool?,windowFullscreen:Bool) -> Bool {
  spaceIsDesktop == false && windowFullscreen
 }
 static func permitsSurface(bundleID:String?,standardWindow:Bool,onScreen:Bool,layer:Int,alpha:Double,ownerMatches:Bool,pointerInside:Bool = true) -> Bool {
  bundleID != nil && standardWindow && onScreen && layer >= 0 && layer < Int(CGWindowLevelForKey(.floatingWindow)) && alpha > 0.01 && ownerMatches && pointerInside
 }
 static func mayBegin() -> Bool {
  // A remembered/focused app window on an ordinary desktop is still desktop
  // context. Reject it before capture, suppression, or any Space request.
  guard DesktopSpace.shared.state()?.desktop == false else {
   log("Source guard rejected: desktop Space or unknown Space"); return false
  }
  guard let app = NSWorkspace.shared.frontmostApplication else { return false }
  let application = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetMessagingTimeout(application,0.06)
  func element(_ owner:AXUIElement,_ key:String) -> AXUIElement? {
   var value:CFTypeRef?
   guard AXUIElementCopyAttributeValue(owner,key as CFString,&value) == .success,
         let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
   return (value as! AXUIElement)
  }
  func text(_ owner:AXUIElement,_ key:String) -> String? {
   var value:CFTypeRef?
   guard AXUIElementCopyAttributeValue(owner,key as CFString,&value) == .success else { return nil }
   return value as? String
  }
  var candidate:AXUIElement?
  if app.bundleIdentifier == "com.apple.finder" {
   // Never use Finder's remembered focused window: desktop focus can retain it.
   var node = element(application,kAXFocusedUIElementAttribute)
   for _ in 0..<12 {
    guard let current = node else { break }
    if text(current,kAXRoleAttribute) == kAXWindowRole { candidate = current; break }
    if let window = element(current,kAXWindowAttribute) { candidate = window; break }
    node = element(current,kAXParentAttribute)
   }
  } else { candidate = element(application,kAXFocusedWindowAttribute) }
  guard let window = candidate else { log("Source guard rejected: no focused window"); return false }
  var fullscreen:CFTypeRef?
  guard AXUIElementCopyAttributeValue(window,"AXFullScreen" as CFString,&fullscreen) == .success,
        permitsContext(spaceIsDesktop:false,windowFullscreen:fullscreen as? Bool ?? false) else {
   log("Source guard rejected: focused window is not native fullscreen"); return false
  }
  // Match AX focus to the actual WindowServer surface. Desktop wallpaper/icon
  // windows have negative levels, and remembered windows can be off-Space.
  typealias WindowIDGetter = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> AXError
  guard let library = dlopen(nil,RTLD_LAZY), let symbol = dlsym(library,"_AXUIElementGetWindow") else {
   log("Source guard rejected: window-ID API unavailable"); return false
  }
  let getter = unsafeBitCast(symbol,to:WindowIDGetter.self)
  var id:CGWindowID = 0
  guard getter(window,&id) == .success, id != 0,
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow,id) as? [[String:Any]],
        let info = windows.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }) else {
   log("Source guard rejected: focused window has no visible surface"); return false
  }
  let layer = info[kCGWindowLayer as String] as? Int ?? -1
  let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
  let bounds = (info[kCGWindowBounds as String] as? [String:Any]).flatMap { CGRect(dictionaryRepresentation:$0 as CFDictionary) }
  let pointerInside = bounds.map { $0.contains(CGEvent(source:nil)?.location ?? CGPoint(x:-100000,y:-100000)) } ?? false
  let standard = text(window,kAXRoleAttribute) == kAXWindowRole
  let matches = (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
  let allowed = permitsSurface(bundleID:app.bundleIdentifier,standardWindow:standard,onScreen:onScreen,layer:layer,alpha:info[kCGWindowAlpha as String] as? Double ?? 0,ownerMatches:matches,pointerInside:pointerInside)
  log("Source guard: role=\(text(window,kAXRoleAttribute) ?? "nil") subrole=\(text(window,kAXSubroleAttribute) ?? "nil") window=\(standard) visible=\(onScreen) layer=\(layer) owner=\(matches) pointerInside=\(pointerInside) allowed=\(allowed)")
  return allowed
 }
}

enum AccessoryDismissal {
 static func minimize(_ app:NSRunningApplication,hideApplication:Bool = true) -> [AXUIElement] {
  let application = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetMessagingTimeout(application,0.25)
  if hideApplication, AXUIElementSetAttributeValue(application,kAXHiddenAttribute as CFString,kCFBooleanTrue) == .success {
   log("Accessory hidden through Accessibility"); return []
  }
  var value:CFTypeRef?
  guard AXUIElementCopyAttributeValue(application,kAXWindowsAttribute as CFString,&value) == .success,
        let windows = value as? [AXUIElement],
        let library = dlopen(nil,RTLD_LAZY), let symbol = dlsym(library,"_AXUIElementGetWindow") else { return [] }
  typealias Getter = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> AXError
  let getter = unsafeBitCast(symbol,to:Getter.self)
  return windows.filter { window in
   var id:CGWindowID = 0
   var alreadyMinimized:CFTypeRef?
   guard AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute as CFString,&alreadyMinimized) == .success,
         alreadyMinimized as? Bool == false,
         getter(window,&id) == .success,
         let surfaces = CGWindowListCopyWindowInfo(.optionIncludingWindow,id) as? [[String:Any]],
         let surface = surfaces.first,
         surface[kCGWindowIsOnscreen as String] as? Bool == true,
         surface[kCGWindowLayer as String] as? Int == 0 else { return false }
   return AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanTrue) == .success
  }
 }
 static func restore(_ windows:[AXUIElement]) {
  var failures = 0
  for window in windows {
   if AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanFalse) != .success { failures += 1 }

  }
  if !windows.isEmpty { log("Window restore requests count=\(windows.count) failures=\(failures)") }
 }
 static func unhide(_ app:NSRunningApplication) {
  _ = app.unhide()
  if app.activationPolicy == .accessory || app.bundleIdentifier == "com.apple.finder" { _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),kAXHiddenAttribute as CFString,kCFBooleanFalse) }
 }
}

final class Suppression {
 static let shared = Suppression()
 private let lock = NSLock(); private var active = false
 var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
 func set(_ value: Bool) { lock.lock(); active = value; lock.unlock() }
 var tap: CFMachPort?
 func install() -> Bool {
  if tap != nil { return true }
  let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
  tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
   if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap = Suppression.shared.tap { CGEvent.tapEnable(tap:tap, enable:true) }
    return Unmanaged.passUnretained(event)
   }
   return Suppression.shared.isActive ? nil : Unmanaged.passUnretained(event)
  }, userInfo:nil)
  guard let tap else { return false }
  CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil,tap,0), .commonModes)
  return true
 }
}

func cgImage(_ image: NSImage) -> CGImage? { image.cgImage(forProposedRect:nil,context:nil,hints:nil) }
func drawImage(_ image: NSImage, in rect: NSRect) { image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1) }

struct Backdrop {
 let clear: CGImage
 let blurred: CGImage
 init(_ image: NSImage) {
  let source = cgImage(image)!
  let scale = min(1,2048.0/Double(source.width))
  let ci = CIImage(cgImage:source).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
  let context = CIContext()
  clear = context.createCGImage(ci,from:ci.extent)!
  let blur = ci.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:18]).cropped(to:ci.extent)
  blurred = context.createCGImage(blur,from:ci.extent)!
 }
}

func dragProgress(_ travel:Double) -> Double { 1-exp(-1.8*max(0,travel)) }

func smoothstep(_ value:Double) -> Double {
 let t = min(1,max(0,value)); return t*t*(3-2*t)
}

struct ReleaseMotion {
 let from: Double
 let target: Double
 let velocity: Double
 var duration: Double { target == 1 ? 0.46 : 0.30 }
 func value(at elapsed: Double) -> Double {
  let t = min(1,max(0,elapsed/duration)), distance = target-from
  guard abs(distance) > 0.0001 else { return target }
  let tangent = max(1.1,min(2.6,velocity/distance*duration))
  let fraction = (tangent-2)*t*t*t + (3-2*tangent)*t*t + tangent*t
  return from+distance*fraction
 }
}

struct StartupCoverGate {
 let shownAt: Double
 private(set) var visibleFrames = 0
 private(set) var ready = false
 mutating func observe(at time:Double,presentationReady:Bool) -> Bool {
  guard !ready else { return true }
  visibleFrames = presentationReady ? visibleFrames+1 : 0
  ready = visibleFrames >= 2 && time-shownAt >= 0.020
  return ready
 }
}

enum MotionStartGate {
 static func allows(coverReady:Bool) -> Bool {
  // Motion follows input. Only revealing the real desktop waits for handoff.
  coverReady
 }
}
enum BackdropPhase {
 static func reveal(_ p:Double) -> Double { smoothstep((p-0.46)/0.48) }
 static func blur(_ p:Double) -> Double { 1-0.85*smoothstep((p-0.40)/0.55) }
 static func zoom(_ p:Double) -> Double { 1.065-0.065*smoothstep(p/0.90) }
}

final class TransitionView: NSView {
 let backdrop = CALayer(), background = CALayer(), blur = CALayer(), card = CALayer()
 var progress = 0.0 { didSet { updateLayers() } }
 private var manualReveal: Double?
 private var desktopReadyAt: Double?
 private var activeRelease: ReleaseMotion?
 private var activeReleaseStart = 0.0
 init(frame:NSRect,snapshot:NSImage,wallpaper:NSImage,icons:[NSImage],cached:Backdrop? = nil) {
  let assets = cached ?? Backdrop(wallpaper)
  super.init(frame:frame)
  wantsLayer = true
  layer = CALayer(); layer!.backgroundColor = NSColor.clear.cgColor
  background.contents = assets.clear; blur.contents = assets.blurred; card.contents = cgImage(snapshot)
  backdrop.frame = bounds; layer!.addSublayer(backdrop)
  for l in [background,blur,card] {
   l.frame = bounds; l.contentsGravity = .resizeAspectFill
   l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
   if l === card { layer!.addSublayer(l) } else { backdrop.addSublayer(l) }
  }
  card.masksToBounds = true
  updateLayers()
 }
 required init?(coder:NSCoder) { fatalError() }
 func playRelease(_ motion:ReleaseMotion) {
  activeRelease = motion; activeReleaseStart = CACurrentMediaTime()
  let duration = motion.duration
  var cardBounds:[NSValue] = [], cardPositions:[NSValue] = [], radii:[Double] = [], alphas:[Double] = []
  var bgBounds:[NSValue] = [], bgPositions:[NSValue] = [], blurs:[Double] = []
  let b = bounds
  for i in 0...90 {
   let t = Double(i)/90*duration
   let p = motion.value(at:t)
   let scale = 1-0.988*p
   cardBounds.append(NSValue(rect:NSRect(x:0,y:0,width:b.width*scale,height:b.height*scale)))
   cardPositions.append(NSValue(point:NSPoint(x:b.midX,y:b.midY+sin(p * .pi)*b.height*0.12)))
   radii.append(28*min(1,p*6)); alphas.append(1-smoothstep((p-0.86)/0.13))
   let zoom = BackdropPhase.zoom(p)
   bgBounds.append(NSValue(rect:NSRect(x:0,y:0,width:b.width*zoom,height:b.height*zoom)))
   bgPositions.append(NSValue(point:NSPoint(x:b.midX,y:b.midY)))
   blurs.append(BackdropPhase.blur(p))
  }
  func animate(_ surface:CALayer,_ key:String,_ values:[Any]) {
   let animation = CAKeyframeAnimation(keyPath:key); animation.values = values
   animation.duration = duration; animation.calculationMode = .linear
   surface.add(animation,forKey:"release.\(key)")
  }
  animate(card,"bounds",cardBounds); animate(card,"position",cardPositions)
  animate(card,"cornerRadius",radii); animate(card,"opacity",alphas)
  for surface in [background,blur] { animate(surface,"bounds",bgBounds); animate(surface,"position",bgPositions) }
  animate(blur,"opacity",blurs)
  if motion.target == 1 { animateRemainingReveal() }
  // Commit to the render server BEFORE sending cross-process Space requests.
  CATransaction.flush()
 }
 private func revealAmount(_ p:Double,at time:Double) -> Double {
  if let manualReveal { return manualReveal }
  guard let ready = desktopReadyAt else { return 0 }
  // A late native handoff is still blended gently; it never uncovers abruptly.
  return BackdropPhase.reveal(p)*smoothstep((time-ready)/0.26)
 }
 func markDesktopReady() {
  guard desktopReadyAt == nil else { return }
  desktopReadyAt = CACurrentMediaTime()
  updateLayers()
  if activeRelease?.target == 1 { animateRemainingReveal() }
 }
 private func animateRemainingReveal() {
  guard let motion = activeRelease else { return }
  backdrop.removeAnimation(forKey:"desktopReveal")
  guard desktopReadyAt != nil else { return }
  let now = CACurrentMediaTime(), elapsed = now-activeReleaseStart
  let duration = max(motion.duration-elapsed,0.28)
  let animation = CAKeyframeAnimation(keyPath:"opacity")
  animation.values = (0...90).map { i in
   let t = Double(i)/90*duration
   return 1-revealAmount(motion.value(at:elapsed+t),at:now+t)
  }
  animation.duration = duration; animation.calculationMode = .linear
  backdrop.add(animation,forKey:"desktopReveal")
 }
 var desktopBlendFinished:Bool {
  guard let ready = desktopReadyAt, CACurrentMediaTime()-ready >= 0.28 else { return false }
  return progress >= 0.999 && (backdrop.presentation()?.opacity ?? backdrop.opacity) <= 0.005
 }
 func blendBackdrop(to opacity:Float,duration:Double = 0.20) {
  let current = backdrop.presentation()?.opacity ?? backdrop.opacity
  let fade = CABasicAnimation(keyPath:"opacity")
  fade.fromValue = current; fade.toValue = opacity; fade.duration = duration
  fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
  manualReveal = 1-Double(opacity); updateLayers()
  backdrop.add(fade,forKey:"desktopReveal")
 }
 func interruptAtPresentation() -> Double {
  let opacity = backdrop.presentation()?.opacity ?? backdrop.opacity
  let width = card.presentation()?.bounds.width ?? card.bounds.width
  let p = max(0,min(1,(1-width/max(1,bounds.width))/0.988))
  for surface in [card,backdrop,background,blur] { surface.removeAllAnimations() }
  activeRelease = nil; desktopReadyAt = nil
  manualReveal = 1-Double(opacity); progress = p
  return p
 }
 func updateLayers() {
  let p = max(0,min(1,progress)), b = bounds
  CATransaction.begin(); CATransaction.setDisableActions(true)
  // Keep the real handoff covered; reveal follows card depth and is reversible.
  let zoom = BackdropPhase.zoom(p)
  let rect = b.insetBy(dx:-b.width*(zoom-1)/2,dy:-b.height*(zoom-1)/2)
  background.frame = rect; blur.frame = rect
  backdrop.opacity = Float(1-revealAmount(p,at:CACurrentMediaTime()))
  background.opacity = 1
  blur.opacity = Float(BackdropPhase.blur(p))
  layer!.backgroundColor = NSColor.clear.cgColor
  let scale = 1 - 0.988*p
  card.bounds = CGRect(x:0,y:0,width:b.width*scale,height:b.height*scale)
  card.position = CGPoint(x:b.midX,y:b.midY+sin(p * .pi)*b.height*0.12)
  card.cornerRadius = 28*min(1,p*6)
  card.opacity = Float(1-smoothstep((p-0.86)/0.13))
  CATransaction.commit()
 }
}

final class OverlayWindow: NSWindow {
 override var canBecomeKey: Bool { true }
 override var canBecomeMain: Bool { false }
 override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?) -> NSRect { frameRect }
 override func keyDown(with event:NSEvent) { if event.keyCode == 53 { if App.shared.returnFailureReported { App.shared.restore() } else { App.shared.cancel() } } }
}

// Read-only private Space metadata; synthetic DockControl switches preserve Dock state.
// No WindowServer mutations, SIP changes, or preference changes.
final class DesktopSpace {
 static let shared = DesktopSpace()
 let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)
 func state(name suppliedName:String? = nil,targetID:UInt64? = nil) -> (desktop:Bool,steps:Int,direction:CGKeyCode,id:UInt64,destinationID:UInt64,nextID:UInt64)? {
  guard let handle, let c = dlsym(handle,"SLSMainConnectionID"), let f = dlsym(handle,"SLSCopyManagedDisplaySpaces") else { return nil }
  let connection = unsafeBitCast(c,to:(@convention(c) ()->Int32).self)()
  let copy = unsafeBitCast(f,to:(@convention(c) (Int32)->Unmanaged<CFArray>).self)
  let displays = copy(connection).takeRetainedValue() as NSArray
  let name = suppliedName ?? displayName()
  guard let display = (displays as? [[String:Any]])?.first(where: { ($0["Display Identifier"] as? String) == name || ($0["Display Identifier"] as? String) == "Main" }),
        let current = display["Current Space"] as? [String:Any], let spaces = display["Spaces"] as? [[String:Any]],
        let id = current["ManagedSpaceID"] as? NSNumber,
        let index = spaces.firstIndex(where: { ($0["ManagedSpaceID"] as? NSNumber) == id }) else { return nil }
  let desktop = (current["type"] as? Int) == 0
  if targetID == nil && desktop { return (true,0,123,id.uint64Value,id.uint64Value,id.uint64Value) }
  let target: Int?
  if let targetID { target = spaces.firstIndex { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == targetID } }
  else {
   let desktops = spaces.indices.filter { (spaces[$0]["type"] as? Int) == 0 }
   target = CommandLine.arguments.contains("--exercise-far-desktop") ? desktops.max { abs($0-index)<abs($1-index) } : desktops.min { abs($0-index)<abs($1-index) }
  }
  guard let target else { return nil }
  let destinationID = (spaces[target]["ManagedSpaceID"] as! NSNumber).uint64Value
  let next = index == target ? index : index+(target < index ? -1 : 1)
  return (desktop,abs(target-index),target < index ? 123 : 124,id.uint64Value,destinationID,(spaces[next]["ManagedSpaceID"] as! NSNumber).uint64Value)
 }
 func displayName() -> String {
  let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
  let displayID = mouseScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
  let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
  return CFUUIDCreateString(nil,uuid) as String
 }
 var gate = SpaceSwitchGate()
 private var route:(id:UInt64,name:String)?
 private var timer:Timer?
 private var routeRequestedAt = 0.0
 private var lastDisplayName:String?
 var isIdle:Bool { route == nil && gate.flight == nil && !gate.failed }
 func settled(at id:UInt64) -> Bool { isIdle && gate.settled(at:id,now:CACurrentMediaTime()) }
 func isAnimating(name:String) -> Bool? {
  typealias Connection = @convention(c) () -> Int32
  typealias Query = @convention(c) (Int32,CFString) -> Bool
  guard let handle, let c = dlsym(handle,"SLSMainConnectionID"), let query = dlsym(handle,"SLSManagedDisplayIsAnimating") else { return nil }
  return unsafeBitCast(query,to:Query.self)(unsafeBitCast(c,to:Connection.self)(),name as CFString)
 }
 func noteSpaceChange() {
  let now = CACurrentMediaTime(); gate.lastNotification = now
  if let name = lastDisplayName, let current = state(name:name) { gate.observe(current.id,at:now,nativeAnimating:isAnimating(name:name)) }
 }
 @discardableResult func switchTowardDesktop(targetID:UInt64? = nil,name:String? = nil) -> UInt64? {
  let display = name ?? displayName()
  guard !gate.failed, let destination = state(name:display,targetID:targetID) else { return nil }
  // Cancellation replaces intent, never the in-flight native transaction.
  route = (destination.destinationID,display); lastDisplayName = display; routeRequestedAt = CACurrentMediaTime()
  log("Native route desired=\(destination.destinationID) inFlight=\(gate.flight?.destination ?? 0)")
  if timer == nil {
   let timer = Timer(timeInterval:0.04,repeats:true) { [weak self] _ in self?.advance() }
   self.timer = timer; RunLoop.main.add(timer,forMode:.common)
  }
  advance()
  return destination.destinationID
 }
 private func advance() {
  guard let route else { return }
  guard let current = state(name:route.name,targetID:route.id) else {
   if CACurrentMediaTime()-routeRequestedAt > 3 {
    gate.failed = true; timer?.invalidate(); timer = nil
    log("Native route target unavailable; refusing further gestures")
   }
   return
  }
  let now = CACurrentMediaTime(), prior = gate.flight
  gate.observe(current.id,at:now,nativeAnimating:isAnimating(name:route.name))
  if gate.failed {
   log("Native route failed to settle; refusing overlapping gestures")
   timer?.invalidate(); timer = nil; return
  }
  if prior != nil && gate.flight == nil { log("Native hop settled=\(current.id)") }
  guard gate.flight == nil else { return }
  if current.id == route.id {
   guard gate.settled(at:route.id,now:now) else { return }
   self.route = nil; timer?.invalidate(); timer = nil
   log("Native route settled=\(current.id)"); return
  }
  guard gate.nativeAnimating != true else { return }
  gate.post(destination:current.nextID,at:now)
  let augmented:Int32 = (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 || CommandLine.arguments.contains("--modern")) ? 1 : 0
  // A single adjacent hop, normal velocity. Recompute the remaining route only
  // after this hop settles; never burst N gestures with N-scaled velocity.
  log("Native hop from=\(current.id) to=\(current.nextID) desired=\(route.id)")
  let direction:Int32 = current.direction == 123 ? -1 : 1
  if hs_space_swipe(direction,augmented) == 0 { gate.failed = true }
 }

}

final class App: NSObject, NSApplicationDelegate {
 static var shared: App!
 var item: NSStatusItem!; var info: NSWindow?
 var statusMenu: StatusMenu?
 var armed = false; var gesture = Gesture(); var overlay: NSWindow?; var transition: TransitionView?
 var pendingEnd: (Bool, Double)?; var committedDuringAnimation: [NSRunningApplication] = []
 var generation = 0; var pendingProgress = 0.0; var finishing = false
 var desktopClearSince = 0.0
 var desktopPreparing = false; var returningToApp = false; var restoreReady = false
 var desktopRouteRetries = 0
 var sourceSpace: UInt64?; var sourceApp:NSRunningApplication?
 var sourceWasFullscreen = false
 var sourceDisplayName = ""
 var sourceWindowID:CGWindowID?
 var desktopSpaceID:UInt64?
 var destinationBackgrounds:[NSWindow] = []
 var localReturn = false
 var desktopSurfaceReady = false; var surfaceProbeInFlight = false
 var returnAppsRestored = false; var returnSurfaceReady = false
 var dismissalInFlight = false; var finderReturnPreparing = false; var returnRestorationStarted = false
 var rollbackApps:[NSRunningApplication] = []; var rollbackWindows:[AXUIElement] = []
 var returnFailureReported = false
 var gestureStartedAt = 0.0; var visualMotionStartedAt = 0.0
 var animationTimer: Timer?; var watchdog: Timer?
 var startupCover = StartupCoverGate(shownAt:0)
 var coverReadyAt = 0.0
 var displayClock: CADisplayLink?
 var animatingRelease = false; var releaseStart = 0.0; var releaseFrom = 0.0; var releaseTarget = 0.0
 var deferredDismissal:(() -> Void)?; var dismissalFinished = false
 var dismissalFinishedAt = 0.0
 var checkInFlight = false
 var nextHandoffCheck = 0.0; var handoffReady = false
 var releaseMotion = ReleaseMotion(from:0,target:1,velocity:0)
 var dragVelocity = 0.0
 var releaseVelocity = 0.0; var handoffStart = 0.0; var lastSpaceChange = 0.0
 var tickTimes:[Double] = []; var updateCosts:[Double] = []
 var backdropCache:[UInt32:Backdrop] = [:]
 var contentCache:SCShareableContent?

 var hiddenApps: [NSRunningApplication] = []
 var minimizedWindows:[AXUIElement] = []; var committedMinimized:[AXUIElement] = []
 var screenPermissionStatus: NSTextField?
 var accessibilityPermissionStatus: NSTextField?
 var escapeMonitor: Any?
 func applicationDidFinishLaunching(_ notification: Notification) {
  applyDockPreference()
  item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
  item.button?.image = MenuBarIcon.make()
  rebuildMenu()
  NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { [weak self] _ in self?.lastSpaceChange = CACurrentMediaTime(); DesktopSpace.shared.noteSpaceChange() }
  warmAssets()
  NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.refreshPermissionStatus() }
  UpdateChecker.shared.activity = { [weak self] in
   guard let self else { return UpdateActivity(gesturesActive:true,transitionActive:true) }
   return UpdateActivity(gesturesActive:self.armed,transitionActive:self.overlay != nil || self.transition != nil || self.finishing || self.pendingEnd != nil || !self.hiddenApps.isEmpty || !self.minimizedWindows.isEmpty)
  }
  UpdateChecker.shared.beforeRestart = { [weak self] in self?.cancel(immediately:true); hs_stop(); Suppression.shared.set(false) }
  NotificationCenter.default.addObserver(forName:Notification.Name("iPhonifyShowAbout"),object:nil,queue:.main){[weak self] _ in self?.showAbout()}
  if !UserDefaults.standard.bool(forKey:PermissionOnboarding.completedKey) { showOnboarding() }
  escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching:.keyDown) { [weak self] event in
   if event.keyCode == 53 { DispatchQueue.main.async { if self?.returnFailureReported == true { self?.restore() } else { self?.cancel() } } }
  }
  log("Started; touch ABI ready")
  if CommandLine.arguments.contains("--request-screen-recording") {
   DispatchQueue.main.async { self.requestScreenRecording() }
  }
 }
 func warmAssets() {
  guard CGPreflightScreenCaptureAccess() else { return }
  for screen in NSScreen.screens {
   let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
   backdropCache[id] = Backdrop(wallpaper(for:screen))
  }
  if CGPreflightScreenCaptureAccess() {
   Task { @MainActor in contentCache = try? await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true) }
  }
 }
 var onboardingWindow: PermissionOnboarding?
 func showOnboarding(){
  settingsWindow?.close()
  if onboardingWindow == nil { onboardingWindow=PermissionOnboarding(controller:self) }
  onboardingWindow?.present()
 }
 var settingsWindow: SettingsWindow?
 func rebuildMenu() {
  if statusMenu == nil {
   statusMenu = StatusMenu(isActive:{[weak self] in self?.armed == true},setActive:{[weak self] requested in
    guard let self, requested != self.armed else { return }
    if !self.armed && !PermissionState.current.ready { self.item.menu?.cancelTracking() }
    self.toggle()
   },openSettings:{[weak self] in self?.showInfo()},quit:{[weak self] in self?.quit()})
   item.menu = statusMenu?.menu
  }
  // Preserve the tracked menu and its views; replacing them makes the live switch disappear.
  statusMenu?.refresh()
  settingsWindow?.updateStatus()
 }
 @objc func showInfo() {
  if onboardingWindow?.window?.isVisible == true { onboardingWindow?.present(); return }
  if settingsWindow == nil { settingsWindow = SettingsWindow(controller:self) }
  settingsWindow?.present()
 }
 func showAbout() {
  if onboardingWindow?.window?.isVisible == true { onboardingWindow?.present(); return }
  showInfo(); settingsWindow?.showAbout()
 }
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
  if !UserDefaults.standard.bool(forKey:PermissionOnboarding.completedKey) { showOnboarding() }
  else { showInfo() }
  return true
 }
 func refreshPermissionStatus() {
  settingsWindow?.updateStatus()
  onboardingWindow?.updateStatus()
  screenPermissionStatus?.stringValue = "Screen Recording: " + (CGPreflightScreenCaptureAccess() ? "Granted" : "Not granted")
  accessibilityPermissionStatus?.stringValue = "Accessibility: " + (AXIsProcessTrusted() ? "Granted" : "Not granted")
 }
 var screenAuthorizationInFlight = false
 @objc func requestScreenRecording() {
  guard !CGPreflightScreenCaptureAccess() else { refreshPermissionStatus(); return }
  guard !screenAuthorizationInFlight else { return }
  screenAuthorizationInFlight = true
  refreshPermissionStatus()
  // Ask through the actual capture framework, from this signed app process.
  // Enumeration registers the capture client; it does not capture image pixels.
  // Never chain a second request API or force Settings navigation afterward.
  Task { @MainActor in
   defer { screenAuthorizationInFlight = false; refreshPermissionStatus() }
   do {
    contentCache = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
    log("Screen Recording authorization request completed")
   } catch {
    let failure = error as NSError
    log("Screen Recording authorization unavailable: domain=\(failure.domain) code=\(failure.code)")
   }
  }
 }
 @objc func requestAccessibility() {
  guard !AXIsProcessTrusted() else { refreshPermissionStatus(); return }
  // An earlier attempt does not prove macOS registered this build. Every
  // explicit Allow click can retry the native request; macOS owns its prompt.
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(options)
  refreshPermissionStatus()
 }
 func alert(_ message: String) { let a = NSAlert(); a.messageText = "iPhonify"; a.informativeText = message; a.runModal() }
 @objc func toggle() {
  if armed { armed = false; hs_stop(); cancel(); rebuildMenu(); return }
  guard PermissionState.current.ready else { showOnboarding(); return }
  guard AXIsProcessTrusted(), Suppression.shared.install() else { alert("Allow Accessibility for iPhonify first. This lets the gesture suppress scrolling while your fingers are in the bottom activation zone."); return }
  armed = hs_start { xy,count,time in
   let points = (0..<Int(count)).map { CGPoint(x:Double(xy![$0*2]),y:Double(xy![$0*2+1])) }
   DispatchQueue.main.async { App.shared.receive(points,at:time) }
  } != 0
  if !armed { alert("The private trackpad API is unavailable on this Mac.") }
  else { info?.orderOut(nil); warmAssets(); log("Armed") }
  rebuildMenu()
 }
 func receive(_ points:[CGPoint],at time:Double) {
  guard armed, !finishing, pendingEnd == nil else { return }
  switch gesture.frame(points,at:time) {
  case .none: break
  case .begin:
   guard begin() else {
    gesture = Gesture(rejected:true)
    log("Ignored gesture: desktop or no eligible fullscreen window")
    return
   }
   Suppression.shared.set(true)
  case .update(let p): pendingProgress = p
  case .end(let commit,let v): if transition == nil && commit { pendingEnd = (commit,v) } else { finish(commit:commit,velocity:v) }
  }
 }
 func wallpaper(for screen:NSScreen) -> NSImage {
  if let url = NSWorkspace.shared.desktopImageURL(for:screen), let image = NSImage(contentsOf:url) { return image }
  let image = NSImage(size:screen.frame.size); image.lockFocus()
  NSGradient(starting:.systemIndigo,ending:.systemTeal)?.draw(in:NSRect(origin:.zero,size:image.size),angle:35)
  image.unlockFocus(); return image
 }
 func phase(_ event:String) {
  log("phase generation=\(generation) elapsedMs=\(Int((CACurrentMediaTime()-gestureStartedAt)*1000)) event=\(event)")
 }
 func makeOverlay(frame:NSRect) -> NSWindow {
  let window = OverlayWindow(contentRect:frame,styleMask:[.borderless],backing:.buffered,defer:false)
  window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.animationBehavior = .none
  window.hidesOnDeactivate = false
  window.level = NSWindow.Level(rawValue:2); window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
  window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
  return window
 }
 @discardableResult func begin() -> Bool {
  guard overlay == nil, !finishing, DesktopSpace.shared.isIdle, GestureSource.mayBegin() else { return false }
  generation += 1; let token = generation; pendingProgress = 0
  sourceDisplayName = DesktopSpace.shared.displayName()
  let initialSpace = DesktopSpace.shared.state(name:sourceDisplayName)
  sourceSpace = initialSpace?.id; sourceWasFullscreen = initialSpace?.desktop == false
  sourceApp = NSWorkspace.shared.frontmostApplication
  sourceWindowID = sourceApp.flatMap { WindowSurfaceProbe.focusedID(pid:$0.processIdentifier) }
  localReturn = false
  desktopSpaceID = nil; desktopSurfaceReady = false; surfaceProbeInFlight = false
  returnAppsRestored = false; returnSurfaceReady = false; returnFailureReported = false
  dismissalInFlight = false; returnRestorationStarted = false; rollbackApps = []; rollbackWindows = []
  log("Source app=\(sourceApp?.bundleIdentifier ?? "nil") fullscreen=\(sourceWasFullscreen) space=\(sourceSpace ?? 0)")
  gestureStartedAt = CACurrentMediaTime(); visualMotionStartedAt = 0
  phase("capture.request")
  desktopPreparing = false; desktopRouteRetries = 0; returningToApp = false; handoffStart = 0; handoffReady = false
  guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
        screen.frame.width > 0, screen.frame.height > 0 else {
   log("Source guard rejected: no usable display"); cleanup(); return false
  }
  watchdog?.invalidate(); watchdog = Timer.scheduledTimer(withTimeInterval:CommandLine.arguments.contains("--exercise-timeout") ? 1.4 : 5,repeats:false) { [weak self] _ in self?.cancel() }
  Task { @MainActor in
   do {
    let content: SCShareableContent
    if let cached = contentCache { content = cached } else { content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true) }
    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw NSError(domain:"Unlock the desktop before trying a transition; no capture display is available",code:1) }
    let filter = SCContentFilter(display:display,excludingWindows:[])
    let config = SCStreamConfiguration(); config.width = Int(screen.frame.width*min(1.5,screen.backingScaleFactor)); config.height = Int(screen.frame.height*min(1.5,screen.backingScaleFactor)); config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
    guard token == generation, !finishing else { return }
    phase("capture.complete")
    let icons: [NSImage] = []
    let view = TransitionView(frame:NSRect(origin:.zero,size:screen.frame.size),snapshot:NSImage(cgImage:image,size:screen.frame.size),wallpaper:wallpaper(for:screen),icons:icons,cached:backdropCache[displayID])
    let window = makeOverlay(frame:screen.frame)
    window.contentView = view; transition = view; overlay = window; view.progress = 0
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    startupCover = StartupCoverGate(shownAt:CACurrentMediaTime()); coverReadyAt = 0
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps:true)
    guard let route = DesktopSpace.shared.state(name:sourceDisplayName),
          let ids = CoverMembership.routeIDs(from:route.id,to:route.destinationID) else {
     log("Desktop blur unavailable: no route"); cancel(immediately:true); return
    }
    for space in ids where space != route.id {
     let bg = NSWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
     bg.isReleasedWhenClosed = false; bg.hasShadow = false
     bg.level = NSWindow.Level(rawValue:1)
     bg.collectionBehavior = [.fullScreenAuxiliary,.stationary]
     bg.ignoresMouseEvents = true; bg.hidesOnDeactivate = false
     bg.backgroundColor = .clear; bg.isOpaque = false; bg.alphaValue = 0
     let content = NSView(frame:NSRect(origin:.zero,size:screen.frame.size)); content.wantsLayer = true
     content.layer = CALayer(); content.layer!.contents = (backdropCache[displayID] ?? Backdrop(wallpaper(for:screen))).blurred
     content.layer!.contentsGravity = .resizeAspectFill
     bg.contentView = content; bg.orderFrontRegardless()
     destinationBackgrounds.append(bg)
     guard CoverMembership.assign(bg,to:space) else {
      log("Desktop blur unavailable: membership failed"); cancel(immediately:true); return
     }
     bg.alphaValue = 1
     log("Destination blur ready space=\(space); only background, no app snapshot")
    }
    CATransaction.flush()
    // Flushing submits layers; it does not mean a frame reached the screen.
    // The display-link barrier below must pass before any Space/app mutation.
    displayClock = view.displayLink(target:self,selector:#selector(tick(_:)))
    displayClock?.preferredFrameRateRange = CAFrameRateRange(minimum:60,maximum:120,preferred:120)
    displayClock?.add(to:.main,forMode:.common)
    tickTimes = []; updateCosts = []
    log("Capture ready")
    if let end = pendingEnd { pendingEnd = nil; finish(commit:end.0,velocity:end.1) }
   } catch { if token == generation { cancel(); log("Capture failed: \(error.localizedDescription)") } }
  }
  return true
 }
 func finish(commit:Bool,velocity:Double) {
  if !commit { cancel(); return }
  guard transition != nil else { cancel(); return }
  guard startupCover.ready, visualMotionStartedAt > 0 else { pendingEnd = (commit,velocity); return }
  watchdog?.invalidate()
  finishing = true; animatingRelease = true
  releaseStart = CACurrentMediaTime(); releaseFrom = transition!.progress
  releaseTarget = commit ? 1 : 0; releaseVelocity = commit ? max(dragVelocity,max(0,velocity)*1.8*exp(-1.8*pendingProgress)/0.48) : min(dragVelocity,min(0,velocity)*1.8*exp(-1.8*pendingProgress)/0.48)
  releaseMotion = ReleaseMotion(from:releaseFrom,target:releaseTarget,velocity:releaseVelocity)
  transition!.playRelease(releaseMotion)
  if commit { phase("gesture.commit"); prepareDesktopBehindCard() }
 }
 func prepareDesktopBehindCard() {
  guard startupCover.ready, !desktopPreparing, !returningToApp else { return }
  desktopPreparing = true; desktopClearSince = 0; nextHandoffCheck = 0
  // Going home changes the active Space only. The user's desktop windows,
  // Finder, minimized state, and app visibility must remain untouched.
  deferredDismissal = nil; dismissalFinished = true
  committedDuringAnimation = []; committedMinimized = []
  if CommandLine.arguments.contains("--exercise-cover-only") { return }
  lastSpaceChange = CACurrentMediaTime()
  phase("native.switch.request")
  desktopSpaceID = DesktopSpace.shared.switchTowardDesktop(name:sourceDisplayName)
 }
 func checkDesktopHandoff(_ now:Double) {
  guard desktopPreparing, !CommandLine.arguments.contains("--exercise-cover-only"),
        !returningToApp, now >= nextHandoffCheck, !checkInFlight else { return }
  nextHandoffCheck = now+0.04; checkInFlight = true
  let name = sourceDisplayName, token = generation
  DispatchQueue.global(qos:.userInteractive).async {
   let state = DesktopSpace.shared.state(name:name)
   DispatchQueue.main.async {
    defer { self.checkInFlight = false }
    guard self.generation == token, !self.returningToApp else { return }
    let routeReady = state?.desktop == true && state?.id == self.desktopSpaceID &&
     self.desktopSpaceID.map({ DesktopSpace.shared.settled(at:$0) }) == true
    if !routeReady { self.desktopSurfaceReady = false }
    if routeReady && !self.desktopSurfaceReady && !self.surfaceProbeInFlight {
     self.surfaceProbeInFlight = true
     Task { @MainActor in
      let healthy = await WindowSurfaceProbe.desktop(displayName:name)
      guard self.generation == token else { return }
      self.surfaceProbeInFlight = false; self.desktopSurfaceReady = healthy
      self.phase("desktop.surface_capture=\(healthy)")
     }
    }
    let ready = routeReady && self.desktopSurfaceReady
    if self.handoffReady && !ready { log("Desktop route changed; returning to source"); self.cancel(); return }
    if !ready { self.desktopClearSince = 0 }
    else if self.desktopClearSince == 0 { self.desktopClearSince = CACurrentMediaTime() }
    self.handoffReady = ready && CACurrentMediaTime()-self.desktopClearSince >= 0.035
    if self.handoffReady && self.handoffStart == 0 {
     self.handoffStart = CACurrentMediaTime(); self.transition?.markDesktopReady()
     self.phase("desktop.ready.preserved_windows")
    }
   }
  }
 }

 @objc func tick(_ clock:CADisplayLink) {
  guard let view = transition else { return }
  let now = CACurrentMediaTime(), workStart = now
  tickTimes.append(now)
  let backgroundAlpha = CGFloat(view.backdrop.presentation()?.opacity ?? view.backdrop.opacity)
  for window in destinationBackgrounds { window.alphaValue = backgroundAlpha }
  if !startupCover.ready && !returningToApp {
   let presented = overlay?.isVisible == true && (view.card.presentation()?.bounds.width ?? 0) >= view.bounds.width-1
   guard startupCover.observe(at:now,presentationReady:presented) else { return }
   coverReadyAt = now
   phase("cover.ready")
   log("Startup cover barrier passed; preparing desktop behind animation")
   prepareDesktopBehindCard()
  }
  checkDesktopHandoff(now)
  if visualMotionStartedAt == 0 && !returningToApp {
   guard !CommandLine.arguments.contains("--exercise-native-only"), !CommandLine.arguments.contains("--exercise-cover-only"), MotionStartGate.allows(coverReady:startupCover.ready) else {
    view.progress = 0
    return
   }
   visualMotionStartedAt = now
   phase("motion.begin")
   if let end = pendingEnd { pendingEnd = nil; finish(commit:end.0,velocity:end.1) }
  }
  if !animatingRelease {
   // Avoid a one-frame catch-up jump if input accumulated during capture.
   let startupWeight = smoothstep((now-visualMotionStartedAt)/0.080)
   let target = dragProgress(pendingProgress)*startupWeight
   let dt = tickTimes.count > 1 ? min(0.05,now-tickTimes[tickTimes.count-2]) : 1/120
   let previous = view.progress
   view.progress += (target-view.progress)*(1-exp(-dt/0.012))
   dragVelocity = (view.progress-previous)/dt
   if view.progress > 0.025 { prepareDesktopBehindCard() }
  } else {
   let elapsed = now-releaseStart
   view.progress = releaseMotion.value(at:elapsed)
   if releaseTarget == 1 {
    // Keep the masking layers until their presentation has actually cleared.
    if elapsed >= releaseMotion.duration && handoffReady && handoffStart > 0 && view.desktopBlendFinished {
     reportFrames(); log("Desktop revealed; desktop Space confirmed=\(handoffReady)"); committedDuringAnimation = []; committedMinimized = []; cleanup(); return
    }
    if elapsed > 2.5 {
     // Never expose a late Space slide or leave an overlay stuck indefinitely.
     log("Desktop handoff timed out; space=\(String(describing:DesktopSpace.shared.state())) hidden=\(committedDuringAnimation.filter { $0.isHidden || $0.isTerminated }.count)/\(committedDuringAnimation.count); restoring hidden apps")
     cancel(); return
    }
   } else {
    if localReturn {
     if elapsed >= releaseMotion.duration {
      sourceApp?.activate(options:[])
      reportFrames(); log("Preview cancelled locally; no Space switch requested")
      cleanup()
     }
     return
    }
    let routeReady = sourceSpace.map { DesktopSpace.shared.settled(at:$0) } ?? DesktopSpace.shared.isIdle
    if routeReady && !dismissalInFlight && !finderReturnPreparing && !returnRestorationStarted { restoreRollbackAfterArrival() }
    if routeReady && returnAppsRestored && !returnSurfaceReady && !surfaceProbeInFlight && now >= nextHandoffCheck {
     nextHandoffCheck = now+0.15; surfaceProbeInFlight = true
     let token = generation, id = sourceWindowID
     Task { @MainActor in
      let healthy:Bool
      if let id, WindowSurfaceProbe.exists(id:id) { healthy = await WindowSurfaceProbe.window(id:id) }
      else { healthy = await WindowSurfaceProbe.desktop(displayName:self.sourceDisplayName) }
      guard self.generation == token else { return }
      self.surfaceProbeInFlight = false; self.returnSurfaceReady = healthy
      self.phase("source.surface_capture=\(healthy)")
     }
    }
    restoreReady = routeReady && returnAppsRestored && returnSurfaceReady
    if elapsed >= releaseMotion.duration && restoreReady {
     sourceApp?.activate(options:[]); reportFrames(); log("Animated return complete; source capture healthy"); cleanup(); return
    }
    if elapsed > 4 && !returnFailureReported {
     returnFailureReported = true; armed = false; hs_stop(); Suppression.shared.set(false)
     displayClock?.invalidate(); displayClock = nil; overlay?.ignoresMouseEvents = false; rebuildMenu()
     log("Return could not be verified; keeping source snapshot. Escape or the menu can dismiss it; gestures disarmed.")
    }
   }
  }
  updateCosts.append(CACurrentMediaTime()-workStart)
 }
 func reportFrames() {
  let intervals = zip(tickTimes.dropFirst(),tickTimes).map { $0-$1 }
  let moving = tickTimes.filter { $0 >= (returningToApp ? releaseStart : visualMotionStartedAt) }
  let movingIntervals = zip(moving.dropFirst(),moving).map { $0-$1 }.sorted()
  let p95 = movingIntervals.isEmpty ? 0 : movingIntervals[min(movingIntervals.count-1,Int(Double(movingIntervals.count)*0.95))]
  let worst = intervals.max() ?? 0
  let meanCost = updateCosts.reduce(0,+)/Double(max(1,updateCosts.count))
  log(String(format:"Frames=%d worstInterval=%.2fms meanLayerUpdate=%.3fms",tickTimes.count,worst*1000,meanCost*1000))
  log(String(format:"Moving frames=%d p95Interval=%.2fms worstInterval=%.2fms",moving.count,p95*1000,(movingIntervals.last ?? 0)*1000))
 }
 func cleanup() {
  desktopPreparing = false; returningToApp = false; deferredDismissal = nil; displayClock?.invalidate(); displayClock = nil; animatingRelease = false
  pendingEnd = nil; generation += 1
  destinationBackgrounds.forEach { $0.orderOut(nil); $0.close() }; destinationBackgrounds = []
  overlay?.orderOut(nil)
  overlay = nil; transition = nil
  finishing = false; dragVelocity = 0; gesture = Gesture()
  // Swallow trailing scroll momentum after lift, too.
  let token = generation
  DispatchQueue.main.asyncAfter(deadline:.now()+0.18) { if self.generation == token { Suppression.shared.set(false) } }
 }
 func cancel(immediately:Bool = false) {
  animationTimer?.invalidate(); watchdog?.invalidate()
  guard let view = transition, !immediately else {
   committedDuringAnimation.forEach { AccessoryDismissal.unhide($0) }; committedDuringAnimation = []
   restoreCommittedWindows()
   cleanup(); return
  }
  if returningToApp { return }
  // Invalidate pending desktop switches, then start at the actual on-screen size.
  generation += 1; deferredDismissal = nil; checkInFlight = false; surfaceProbeInFlight = false; pendingEnd = nil
  releaseFrom = view.interruptAtPresentation()
  returningToApp = true; finishing = true; animatingRelease = true; restoreReady = false; returnAppsRestored = false; returnSurfaceReady = false
  releaseTarget = 0; releaseStart = CACurrentMediaTime(); nextHandoffCheck = 0
  releaseMotion = ReleaseMotion(from:releaseFrom,target:0,velocity:min(0,dragVelocity))
  view.blendBackdrop(to:1,duration:0.10)
  view.playRelease(releaseMotion)
  if !desktopPreparing {
   localReturn = true
   log("Local preview rollback began; native Space remains unchanged")
   return
  }
  enqueueRollback(apps:committedDuringAnimation,windows:committedMinimized)
  committedDuringAnimation = []; committedMinimized = []; returnRestorationStarted = false; finderReturnPreparing = true
  let token = generation
  DispatchQueue.main.asyncAfter(deadline:.now()+0.12) {
   guard self.generation == token, self.returningToApp else { return }
   // Cover the desktop before bringing the original full-screen Space back.
   // Otherwise its full-size surface can flash behind the growing snapshot.
   self.prepareFinderReturn(token:token)
  }
  log("Animated rollback began")
 }
 func prepareFinderReturn(token:Int) {
  // A late hide operation must finish before its saved window state is undone.
  if dismissalInFlight {
   DispatchQueue.main.asyncAfter(deadline:.now()+0.04) { if self.generation == token { self.prepareFinderReturn(token:token) } }
   return
  }
  let windows = rollbackWindows, protect = sourceWasFullscreen && sourceApp?.bundleIdentifier == "com.apple.finder"
  DispatchQueue.global(qos:.userInteractive).async {
   let prepared = FinderDismissal.prepareReturn(windows,protectSource:protect)
   DispatchQueue.main.async {
    guard self.generation == token else { prepared.unhide.forEach { AccessoryDismissal.unhide($0) }; return }
    self.rollbackWindows.removeAll { saved in prepared.windows.contains { CFEqual(saved,$0) } }
    self.minimizedWindows.removeAll { saved in prepared.windows.contains { CFEqual(saved,$0) } }
    self.enqueueRollback(apps:prepared.unhide,windows:[])
    for app in prepared.unhide where !self.hiddenApps.contains(where: { $0.processIdentifier == app.processIdentifier }) { self.hiddenApps.append(app) }
    guard prepared.verified else { self.phase("finder.return_state.unverified"); return }
    self.finderReturnPreparing = false
    self.phase("finder.return_state.prepared")
    if let source = self.sourceSpace { DesktopSpace.shared.switchTowardDesktop(targetID:source,name:self.sourceDisplayName) }
   }
  }
 }
 func enqueueRollback(apps:[NSRunningApplication],windows:[AXUIElement]) {
  if !apps.isEmpty || !windows.isEmpty { returnAppsRestored = false }
  for app in apps where !rollbackApps.contains(where: { $0.processIdentifier == app.processIdentifier }) { rollbackApps.append(app) }
  for window in windows where !rollbackWindows.contains(where: { CFEqual($0,window) }) {
   rollbackWindows.append(window)
   if !minimizedWindows.contains(where: { CFEqual($0,window) }) { minimizedWindows.append(window) }
  }
 }
 func restoreRollbackAfterArrival() {
  returnRestorationStarted = true
  let apps = rollbackApps, windows = rollbackWindows, token = generation
  phase("source.restore_requests.after_arrival")
  DispatchQueue.global(qos:.userInteractive).async {
   apps.forEach { AccessoryDismissal.unhide($0) }; AccessoryDismissal.restore(windows)
   DispatchQueue.main.async {
    guard self.generation == token else { return }
    self.hiddenApps.removeAll { saved in apps.contains { $0.processIdentifier == saved.processIdentifier } }
    self.minimizedWindows.removeAll { saved in windows.contains { CFEqual(saved,$0) } }
    self.rollbackApps.removeAll { saved in apps.contains { $0.processIdentifier == saved.processIdentifier } }
    self.rollbackWindows.removeAll { saved in windows.contains { CFEqual(saved,$0) } }
    self.returnAppsRestored = self.rollbackApps.isEmpty && self.rollbackWindows.isEmpty
    if !self.returnAppsRestored { self.returnRestorationStarted = false }
   }
  }
 }
 func restoreCommittedWindows() {
  AccessoryDismissal.restore(committedMinimized)
  minimizedWindows.removeAll { saved in committedMinimized.contains { CFEqual(saved,$0) } }; committedMinimized = []
 }
 @objc func restore() {
  if transition != nil && !returnFailureReported {
   cancel(); enqueueRollback(apps:hiddenApps,windows:minimizedWindows); return
  }
  cancel(immediately:true)
  let finderReturn = DesktopSpace.shared.state()?.desktop == true
   ? FinderDismissal.prepareReturn(minimizedWindows,protectSource:false)
   : (windows:[AXUIElement](),unhide:[NSRunningApplication](),verified:true)
  hiddenApps.forEach { AccessoryDismissal.unhide($0) }; hiddenApps = []
  finderReturn.unhide.forEach { AccessoryDismissal.unhide($0) }
  let remaining = minimizedWindows.filter { saved in !finderReturn.windows.contains { CFEqual(saved,$0) } }
  AccessoryDismissal.restore(remaining); minimizedWindows = []
  rollbackApps = []; rollbackWindows = []
 }
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  UpdateChecker.shared.permitsTermination() ? .terminateNow : .terminateCancel
 }
 @objc func quit() { guard UpdateChecker.shared.permitsTermination() else { showAbout();return }; cancel(immediately:true); hiddenApps.forEach { AccessoryDismissal.unhide($0) }; AccessoryDismissal.restore(minimizedWindows); hs_stop(); NSApp.terminate(nil) }
 func applicationWillTerminate(_ notification:Notification) { hiddenApps.forEach { AccessoryDismissal.unhide($0) }; AccessoryDismissal.restore(minimizedWindows); Suppression.shared.set(false); hs_stop() }
}

func selfTest() {
 precondition(!GestureSource.permitsContext(spaceIsDesktop:true,windowFullscreen:false),"focused app on desktop must be rejected")
 precondition(!GestureSource.permitsContext(spaceIsDesktop:true,windowFullscreen:true),"stale fullscreen focus on a desktop must be rejected")
 precondition(!GestureSource.permitsContext(spaceIsDesktop:nil,windowFullscreen:true),"unknown Space must fail closed")
 precondition(!GestureSource.permitsContext(spaceIsDesktop:false,windowFullscreen:false),"floating app over a fullscreen Space must be rejected")
 precondition(GestureSource.permitsContext(spaceIsDesktop:false,windowFullscreen:true),"actual native fullscreen window is eligible")
 print("PASS: desktop/focused-app, stale fullscreen focus, unknown Space, and floating-window context rejection")

 var native = SpaceSwitchGate()
 native.observe(10,at:0,nativeAnimating:false); native.post(destination:20,at:0)
 native.observe(20,at:0.02,nativeAnimating:true)
 native.observe(20,at:0.5,nativeAnimating:true)
 precondition(native.flight != nil && !native.settled(at:20,now:0.5),"native animation cannot be bypassed by elapsed time")
 native.observe(20,at:0.51,nativeAnimating:false)
 precondition(native.settled(at:20,now:0.51),"completed native animation can settle without another arbitrary delay")
 print("PASS: native animation status gates completion; timed fallback remains for unavailable API")
 // A cancellation arriving before the forward metadata update must not post
 // a reverse gesture until the already-posted forward hop has settled.
 var route = SpaceSwitchGate()
 route.observe(10,at:0); route.post(destination:20,at:0.01)
 route.observe(10,at:0.14)
 precondition(route.flight != nil && !route.settled(at:10,now:0.14))
 route.observe(20,at:0.15); route.lastNotification = 0.20
 route.observe(20,at:0.32)
 precondition(route.flight == nil && route.settled(at:20,now:0.32))
 route.post(destination:10,at:0.33)
 route.observe(10,at:0.35); route.observe(10,at:0.64)
 precondition(route.settled(at:10,now:0.64))
 // Metadata which changes early, bounces, or stops arriving cannot release
 // the transaction gate or permit a burst of additional native gestures.
 var bouncing = SpaceSwitchGate()
 bouncing.observe(10,at:0); bouncing.post(destination:20,at:0)
 bouncing.observe(20,at:0.02); bouncing.observe(10,at:0.20)
 bouncing.observe(20,at:0.31)
 precondition(bouncing.flight != nil)
 bouncing.lastNotification = 0.40; bouncing.observe(20,at:0.45)
 precondition(bouncing.flight != nil)
 bouncing.observe(20,at:0.53)
 precondition(bouncing.settled(at:20,now:0.53))
 var timeout = SpaceSwitchGate()
 timeout.observe(10,at:0); timeout.post(destination:20,at:0)
 timeout.observe(10,at:3.1)
 precondition(timeout.failed && !timeout.settled(at:10,now:3.1))
 print("PASS: serialized native switch, early cancellation, bouncing metadata, notification settling, and timeout rejection")
 func points(_ y:Double,_ x:Double = 0.5) -> [CGPoint] { [CGPoint(x:x-0.05,y:y),CGPoint(x:x+0.05,y:y)] }
 var g = Gesture()
 guard case .none = g.frame(points(0.02),at:0) else { fatalError("edge contact must not activate") }
 guard case .none = g.frame(points(0.04),at:0.05) else { fatalError("small scroll must not activate") }
 guard case .begin = g.frame(points(0.10),at:0.1) else { fatalError("deliberate edge entry") }
 _ = g.frame(points(0.4),at:0.2)
 guard case .end(true,_) = g.frame([],at:0.22) else { fatalError("commit") }
 _ = g.frame(points(0.15),at:1)
 guard case .none = g.frame(points(0.4),at:1.1) else { fatalError("ordinary scroll rejection") }
 _ = g.frame([],at:2); _ = g.frame(points(0.02),at:2.01)
 guard case .none = g.frame(points(0.12),at:2.4) else { fatalError("slow scroll rejection") }
 _ = g.frame([],at:3); _ = g.frame(points(0.02),at:3.01)
 guard case .none = g.frame(points(0.10,0.6),at:3.1) else { fatalError("diagonal rejection") }
 _ = g.frame([],at:4); _ = g.frame(points(0.02),at:4.01); _ = g.frame(points(0.10),at:4.1)
 _ = g.frame(points(0.11),at:4.2)
 guard case .end(false,_) = g.frame([],at:4.3) else { fatalError("short gesture cancellation") }
 _ = g.frame(points(0.02),at:5); _ = g.frame(points(0.10),at:5.1); _ = g.frame(points(0.4),at:5.2)
 guard case .end(true,_) = g.frame([CGPoint(x:0.5,y:0.4)],at:5.3) else { fatalError("staggered lift") }
 _ = g.frame([],at:6); _ = g.frame([CGPoint(x:0.5,y:0.02)],at:6.01)
 guard case .none = g.frame(points(0.02),at:6.3) else { fatalError("resting finger rejection") }
 var oneMoves = Gesture(); _ = oneMoves.frame(points(0.02),at:7)
 guard case .none = oneMoves.frame([CGPoint(x:0.45,y:0.02),CGPoint(x:0.55,y:0.2)],at:7.1) else { fatalError("both fingers must move") }
 for from in [0.12,0.35,0.76] {
  for target in [0.0,1.0] {
   for speed in [0.0,1.5,5.0] {
    let motion = ReleaseMotion(from:from,target:target,velocity:target > from ? speed : -speed)
    var previous = from
    for i in 0...100 {
     let p = motion.value(at:Double(i)/100*motion.duration)
     precondition(p >= -0.00001 && p <= 1.00001,"motion stays bounded")
     precondition(target > from ? p >= previous-0.00001 : p <= previous+0.00001,"monotonic motion")
     previous = p
    }
    precondition(abs(previous-target)<0.00001,"motion reaches destination")
   }
  }
 }
 precondition(GestureSource.permitsSurface(bundleID:"test.app",standardWindow:true,onScreen:true,layer:0,alpha:1,ownerMatches:true),"visible standard surface passes surface checks")
 precondition(!GestureSource.permitsSurface(bundleID:"com.apple.finder",standardWindow:true,onScreen:true,layer:-2147483603,alpha:1,ownerMatches:true),"desktop surfaces are never eligible")
 precondition(!GestureSource.permitsSurface(bundleID:"test.app",standardWindow:true,onScreen:false,layer:0,alpha:1,ownerMatches:true),"stale off-Space app focus is rejected")
 precondition(!GestureSource.permitsSurface(bundleID:"test.app",standardWindow:true,onScreen:true,layer:0,alpha:0,ownerMatches:true),"invisible window is rejected")
 precondition(!GestureSource.permitsSurface(bundleID:"test.app",standardWindow:true,onScreen:true,layer:0,alpha:1,ownerMatches:false),"wrong surface owner is rejected")
 precondition(!GestureSource.permitsSurface(bundleID:nil,standardWindow:true,onScreen:true,layer:0,alpha:1,ownerMatches:true),"unknown source is rejected")
 precondition(!GestureSource.permitsSurface(bundleID:"test.app",standardWindow:true,onScreen:true,layer:0,alpha:1,ownerMatches:true,pointerInside:false),"pointer on exposed desktop cannot claim an app gesture")
 print("PASS: desktop surface, stale focus, invisible surface, and owner rejection")
 precondition(!MotionStartGate.allows(coverReady:false),"motion waits for the cover")
 precondition(MotionStartGate.allows(coverReady:true),"motion must not wait for native handoff")
 print("PASS: responsive motion gate")
 var startup = StartupCoverGate(shownAt:100)
 precondition(!startup.observe(at:100.008,presentationReady:false),"no mutation without a presented layer")
 precondition(!startup.observe(at:100.016,presentationReady:true),"one frame cannot open the cover gate")
 precondition(startup.observe(at:100.025,presentationReady:true),"two presented frames establish the cover")
 var delayedStartup = StartupCoverGate(shownAt:100)
 precondition(!delayedStartup.observe(at:100.050,presentationReady:false),"elapsed time alone cannot open the gate")
 precondition(!delayedStartup.observe(at:100.060,presentationReady:true),"late first frame still needs a second frame")
 precondition(delayedStartup.observe(at:100.070,presentationReady:true),"late cover opens after two ready observations")
 print("PASS: startup presentation gate and delayed first-frame handling")
 precondition(BackdropPhase.reveal(0.4) == 0,"large card keeps desktop covered")
 precondition(BackdropPhase.blur(0.35) == 1,"keep initial native handoff blurred")
 precondition(BackdropPhase.reveal(0.70) > 0 && BackdropPhase.reveal(0.70) < 1,"small card gradually reveals desktop")
 precondition(BackdropPhase.reveal(0.95) == 1,"desktop clears behind final tiny card")
 precondition(BackdropPhase.reveal(0.4) < BackdropPhase.reveal(0.7),"reversing travel covers desktop again")
 print("PASS: layered cover, delayed reveal, and reversible depth curve")
 precondition(dragProgress(1.5) > dragProgress(1) && dragProgress(2) > dragProgress(1.5),"long drag must keep shrinking")
 print("PASS: release/return continuity, monotonicity and completion across eighteen swipe conditions")
 print("PASS: deliberate edge entry, normal/slow/diagonal scroll rejection, resting finger rejection, both-finger travel, cancellation, staggered lift")
}
if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
let app = NSApplication.shared
let delegate = App(); App.shared = delegate; app.delegate = delegate
app.run()
