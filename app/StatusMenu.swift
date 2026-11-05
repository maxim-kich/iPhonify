// SPDX-License-Identifier: MIT
// Native menu geometry and separators follow MagDot by Maxim Kich.
import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
 let menu = NSMenu()
 let activation = NSSwitch()
 private let isActive: () -> Bool
 private let setActive: (Bool) -> Void
 private let openSettings: () -> Void
 private let quit: () -> Void

 init(isActive: @escaping () -> Bool, setActive: @escaping (Bool) -> Void,
      openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
  self.isActive = isActive; self.setActive = setActive
  self.openSettings = openSettings; self.quit = quit
  super.init()
  menu.autoenablesItems = false; menu.delegate = self
  let item = NSMenuItem()
  let row = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
  let label = NSTextField(labelWithString: "Activate")
  label.font = .systemFont(ofSize: 13); label.sizeToFit()
  label.frame.origin = NSPoint(x: 16, y: (row.bounds.height - label.frame.height) / 2)
  row.addSubview(label)
  activation.frame = NSRect(x: 164, y: 8, width: 40, height: 24)
  activation.target = self; activation.action = #selector(changeActivation)
  activation.setAccessibilityLabel("Activate iPhonify")
  row.addSubview(activation); item.view = row
  menu.addItem(item); menu.addItem(.separator())
  let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
  settings.target = self; menu.addItem(settings); menu.addItem(.separator())
  let quit = NSMenuItem(title: "Quit iPhonify", action: #selector(quitApp), keyEquivalent: "q")
  quit.target = self; menu.addItem(quit)
  refresh()
 }
 func refresh() {
  let state: NSControl.StateValue = isActive() ? .on : .off
  if activation.state != state { activation.state = state }
 }
 func menuWillOpen(_ menu: NSMenu) { refresh() }
 @objc func changeActivation() {
  let requested = activation.state == .on
  if requested != isActive() { setActive(requested) }
  refresh()
 }
 @objc private func showSettings() { openSettings() }
 @objc private func quitApp() { quit() }
}
