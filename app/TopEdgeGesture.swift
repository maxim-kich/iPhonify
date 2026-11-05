// SPDX-License-Identifier: GPL-3.0-only
import AppKit

struct TopEdgeGesture {
 enum Target { case appleMenu, controlCenter }
 enum Action { case none, begin, end(Target?) }
 private var target: Target?
 private var initial: [CGPoint] = []
 private var firstContactTime: Double?
 private var startedAt = 0.0
 private var engaged = false
 private var rejected = false
 private var travel = 0.0
 private var peakTravel = 0.0

 mutating func frame(_ points: [CGPoint], at time: Double) -> Action {
  // Wait for every finger to lift before allowing a new contact sequence.
  if points.isEmpty {
   let result: Action = engaged ? .end(!rejected && travel >= 0.18 && time-startedAt <= 0.8 ? target : nil) : .none
   self = TopEdgeGesture()
   return result
  }
  guard !rejected else { return .none }
  func reject() -> Action {
   rejected = true
   let result: Action = engaged ? .end(nil) : .none
   engaged = false
   return result
  }
  guard points.count <= 2 else { return reject() }
  if initial.isEmpty {
   // Both fingers must originate in the top 3%, in the same outer third.
   guard points.allSatisfy({ $0.y >= 0.97 }) else { return reject() }
   let side: Target
   if points.allSatisfy({ $0.x < 1.0/3 }) { side = .appleMenu }
   else if points.allSatisfy({ $0.x > 2.0/3 }) { side = .controlCenter }
   else { return reject() }
   if let target, target != side { return reject() }
   target = side
   if firstContactTime == nil { firstContactTime = time }
   guard time-(firstContactTime ?? time) <= 0.12 else { return reject() }
   guard points.count == 2 else { return .none }
   initial = points.sorted { $0.x < $1.x }; startedAt = time
   return .none
  }
  if points.count == 1 && engaged {
   let result: Action = .end(travel >= 0.18 && time-startedAt <= 0.8 ? target : nil)
   engaged = false; rejected = true
   return result
  }
  guard points.count == 2, time-startedAt <= 0.8 else { return reject() }
  let sorted = points.sorted { $0.x < $1.x }
  let moves = zip(sorted,initial).map { $0.1.y-$0.0.y }
  let dx = zip(sorted,initial).map { abs($0.0.x-$0.1.x) }.max() ?? 1
  travel = moves.reduce(0,+)/2
  peakTravel = max(peakTravel,travel)
  guard dx <= 0.04, moves.allSatisfy({ $0 >= -0.012 }), peakTravel-travel < 0.06,
        points.allSatisfy({ target == .appleMenu ? $0.x < 0.5 : $0.x > 0.5 }) else { return reject() }
  if !engaged {
   guard time-startedAt <= 0.28 else { return reject() }
   if travel >= 0.12 && moves.allSatisfy({ $0 >= 0.10 }) {
    engaged = true
    return .begin
   }
  }
  return .none
 }
}

enum TopEdgeMenu {
 @discardableResult static func open(_ target: TopEdgeGesture.Target) -> Bool {
  guard AXIsProcessTrusted() else { return false }
  switch target {
  case .controlCenter:
   // Native Globe-C shortcut; independent of menu bar position and language.
   guard let source = CGEventSource(stateID:.hidSystemState),
         let down = CGEvent(keyboardEventSource:source,virtualKey:8,keyDown:true),
         let up = CGEvent(keyboardEventSource:source,virtualKey:8,keyDown:false) else { return false }
   down.flags = .maskSecondaryFn; up.flags = .maskSecondaryFn
   down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
   return true
  case .appleMenu:
   guard let app = NSWorkspace.shared.frontmostApplication else { return false }
   let application = AXUIElementCreateApplication(app.processIdentifier)
   AXUIElementSetMessagingTimeout(application,0.25)
   var bar: CFTypeRef?
   guard AXUIElementCopyAttributeValue(application,kAXMenuBarAttribute as CFString,&bar) == .success,
         let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
   var children: CFTypeRef?
   guard AXUIElementCopyAttributeValue(bar as! AXUIElement,kAXChildrenAttribute as CFString,&children) == .success,
         let items = children as? [AXUIElement], let apple = items.first else { return false }
   return AXUIElementPerformAction(apple,kAXPressAction as CFString) == .success
  }
 }
}

func topEdgeGestureSelfTest() {
 func pair(_ x:Double,_ y:Double) -> [CGPoint] { [CGPoint(x:x-0.04,y:y),CGPoint(x:x+0.04,y:y)] }
 for (x,target) in [(0.2,TopEdgeGesture.Target.appleMenu),(0.8,.controlCenter)] {
  var g = TopEdgeGesture()
  _ = g.frame(pair(x,0.99),at:0)
  guard case .none = g.frame(pair(x,0.91),at:0.1) else { fatalError("short swipe must not engage") }
  guard case .begin = g.frame(pair(x,0.85),at:0.2) else { fatalError("deliberate swipe begins") }
  _ = g.frame(pair(x,0.75),at:0.3)
  guard case .end(let actual) = g.frame([],at:0.32), actual == target else { fatalError("top edge target") }
  guard case .none = g.frame([],at:0.4) else { fatalError("duplicate action") }
 }
 // Ordinary scrolling, centre starts, old broad zone and three fingers never claim scrolling.
 for start in [pair(0.2,0.95),pair(0.8,0.7),pair(0.5,0.99),pair(0.4,0.99),pair(0.8,0.99)+[CGPoint(x:0.9,y:0.99)]] {
  var g = TopEdgeGesture()
  guard case .none = g.frame(start,at:0) else { fatalError("invalid start") }
  guard case .none = g.frame(pair(0.8,0.7),at:0.1) else { fatalError("invalid start must stay rejected") }
  guard case .none = g.frame([],at:0.2) else { fatalError("rejected lift") }
 }
 // Interrupted, reversing, diagonal and stale contact sequences must cancel.
 for end in [pair(0.8,0.98),pair(0.9,0.7),pair(0.8,0.7)+[CGPoint(x:0.9,y:0.7)],[CGPoint(x:0.8,y:0.7)]] {
  var g = TopEdgeGesture()
  _ = g.frame(pair(0.8,0.99),at:0)
  _ = g.frame(pair(0.8,0.85),at:0.1)
  guard case .end(nil) = g.frame(end,at:0.2) else { fatalError("invalid continuation cancels") }
  guard case .none = g.frame(pair(0.8,0.7),at:0.3) else { fatalError("no rearm before lift") }
  _ = g.frame([],at:0.4)
 }
 var short = TopEdgeGesture()
 _ = short.frame(pair(0.2,0.99),at:0)
 _ = short.frame(pair(0.2,0.85),at:0.1)
 guard case .end(nil) = short.frame([],at:0.2) else { fatalError("insufficient travel") }
 var stale = TopEdgeGesture()
 _ = stale.frame(pair(0.2,0.99),at:0)
 _ = stale.frame(pair(0.2,0.75),at:0.1)
 guard case .end(nil) = stale.frame([],at:1) else { fatalError("stale release") }
 var staggered = TopEdgeGesture()
 _ = staggered.frame([CGPoint(x:0.8,y:0.99)],at:0)
 _ = staggered.frame(pair(0.8,0.99),at:0.05)
 guard case .begin = staggered.frame(pair(0.8,0.75),at:0.2) else { fatalError("staggered fingers") }
 guard case .end(.controlCenter) = staggered.frame([],at:0.3) else { fatalError("staggered commit") }
 var lift = TopEdgeGesture()
 _ = lift.frame(pair(0.8,0.99),at:0)
 _ = lift.frame(pair(0.8,0.75),at:0.1)
 guard case .end(.controlCenter) = lift.frame([CGPoint(x:0.8,y:0.75)],at:0.2) else { fatalError("staggered lift commits once") }
 guard case .none = lift.frame([],at:0.21) else { fatalError("staggered lift duplicate") }
 var oneMoves = TopEdgeGesture()
 _ = oneMoves.frame(pair(0.8,0.99),at:0)
 guard case .none = oneMoves.frame([CGPoint(x:0.76,y:0.99),CGPoint(x:0.84,y:0.70)],at:0.1) else { fatalError("both fingers must travel") }
 print("PASS: top-edge deliberate routing, narrow zones, short swipe, cancellation, timeout, staggered fingers and single action")
}
