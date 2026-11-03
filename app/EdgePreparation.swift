import AppKit

// Identity and age must still match when speculative capture becomes visible.
struct PreparationIdentity: Equatable {
 let pid: pid_t
 let window: CGWindowID
 let space: UInt64
 let display: CGDirectDisplayID
 let screenFrame: NSRect
 let scale: CGFloat
 func permitsReuse(as current:PreparationIdentity,age:Double) -> Bool {
  self == current && age >= 0 && age <= 0.35
 }
}

final class EdgePreparation {
 let identity: PreparationIdentity
 let screen: NSScreen
 let startedAt: Double
 var claimed = false
 var window: NSWindow?
 var view: TransitionView?
 var task: Task<Void,Never>?
 init(identity:PreparationIdentity,screen:NSScreen,at time:Double) {
  self.identity = identity; self.screen = screen; startedAt = time
 }
}
