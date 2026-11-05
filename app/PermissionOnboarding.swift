// SPDX-License-Identifier: MIT
// First-run window structure adapted from MagDot by Maxim Kich.
import AppKit
import ApplicationServices

final class PermissionOnboarding: NSWindowController, NSWindowDelegate {
 static let completedKey = "permissionOnboardingCompleted"
 weak var controller: App?
 let accessButton = NSButton(title: "Allow…", target: nil, action: nil)
 let screenButton = NSButton(title: "Allow…", target: nil, action: nil)
 let accessStatus = NSTextField(labelWithString: "Allowed")
 let screenStatus = NSTextField(labelWithString: "Allowed")
 let done = NSButton(title: "Done", target: nil, action: nil)
 var timer: Timer?

 init(controller: App) {
  self.controller = controller
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
  window.title = "Welcome to iPhonify"; window.isReleasedWhenClosed = false
  super.init(window: window); window.delegate = self
  let content = window.contentView!
  let icon = NSImageView(frame: NSRect(x: 28, y: 206, width: 64, height: 64))
  icon.image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
  icon.imageScaling = .scaleProportionallyUpOrDown; content.addSubview(icon)
  content.addSubview(settingsLabel("iPhonify", NSRect(x: 104, y: 242, width: 348, height: 28), size: 18))
  content.addSubview(settingsLabel("Allow these permissions to use iPhonify. Gestures stay off until you activate them.", NSRect(x: 104, y: 198, width: 348, height: 42), secondary: true))
  for (index, title) in ["Accessibility", "Screen Recording"].enumerated() {
   let card = settingsCard(NSRect(x: 24, y: 118 - index * 64, width: 432, height: 54)); content.addSubview(card)
   card.contentView?.addSubview(settingsLabel(title, NSRect(x: 16, y: 16, width: 245, height: 22)))
   let status = [accessStatus, screenStatus][index]
   status.frame = NSRect(x: 316, y: 16, width: 100, height: 22); status.alignment = .right; status.textColor = .systemGreen; card.contentView?.addSubview(status)
   let button = [accessButton, screenButton][index]
   button.frame = NSRect(x: 316, y: 11, width: 100, height: 32); button.bezelStyle = .rounded; button.target = self
   button.action = index == 0 ? #selector(allowAccess) : #selector(allowScreen); card.contentView?.addSubview(button)
  }
  done.target = self; done.action = #selector(finish); done.bezelStyle = .rounded; done.keyEquivalent = "\r"
  done.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(done)
  NSLayoutConstraint.activate([
   done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
   done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -15),
   done.widthAnchor.constraint(equalToConstant: 100), done.heightAnchor.constraint(equalToConstant: 32)
  ])
  window.center(); updateStatus()
 }
 required init?(coder: NSCoder) { fatalError() }
 func present() {
  showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); updateStatus()
  if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() } }
 }
 func updateStatus() {
  let state = PermissionState.current
  accessButton.title = "Allow…"
  screenButton.title = controller?.screenAuthorizationInFlight == true ? "Requesting…" : "Allow…"
  screenButton.isEnabled = controller?.screenAuthorizationInFlight != true
  accessStatus.isHidden = !state.accessibility; accessButton.isHidden = state.accessibility
  screenStatus.isHidden = !state.screenRecording; screenButton.isHidden = state.screenRecording
  done.isEnabled = state.ready
 }
 func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }
 @objc func allowAccess() { controller?.requestAccessibility(); updateStatus() }
 @objc func allowScreen() { controller?.requestScreenRecording(); updateStatus() }
 @objc func finish() {
  guard PermissionState.current.ready else { updateStatus(); return }
  UserDefaults.standard.set(true, forKey: Self.completedKey); close()
 }
}
