import Foundation

// One posted native gesture must settle before another can be posted. Changing
// the desired route does not invalidate events already handed to WindowServer.
struct SpaceSwitchGate {
 struct Flight { let destination:UInt64; let sentAt:Double }
 var flight:Flight?
 var observed:UInt64?
 var stableSince = 0.0
 var lastNotification = -Double.infinity
 var failed = false
 var nativeAnimating:Bool?
 private var minimumAge:Double { nativeAnimating == nil ? 0.30 : 0.04 }
 private var quietTime:Double { nativeAnimating == nil ? 0.12 : 0.04 }
 mutating func observe(_ id:UInt64,at now:Double,nativeAnimating:Bool? = nil) {
  self.nativeAnimating = nativeAnimating
  if observed != id { observed = id; stableSince = now }
  if let flight, id == flight.destination, nativeAnimating != true,
     now-flight.sentAt >= minimumAge,
     now-stableSince >= quietTime, now-lastNotification >= quietTime { self.flight = nil }
  if let flight, now-flight.sentAt > 3 { failed = true }
 }
 func settled(at id:UInt64,now:Double) -> Bool {
  !failed && nativeAnimating != true && flight == nil && observed == id && now-stableSince >= quietTime && now-lastNotification >= quietTime
 }
 mutating func post(destination:UInt64,at now:Double) {
  precondition(flight == nil && !failed,"Never overlap native Space gestures")
  flight = Flight(destination:destination,sentAt:now)
 }
}
