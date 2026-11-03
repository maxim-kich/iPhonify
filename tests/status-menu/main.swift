import AppKit
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
var active=false
var changes=0
let controller=StatusMenu(isActive:{active},setActive:{active=$0;changes += 1},openSettings:{},quit:{})
let menu=controller.menu
let row=menu.items[0].view!
precondition(menu.items.count == 5 && menu.items[1].isSeparatorItem && menu.items[3].isSeparatorItem)
precondition(row.frame.size == NSSize(width:220,height:40))
for value in [true,false,true,false] {
 controller.activation.state=value ? .on:.off
 controller.changeActivation()
 precondition(active == value)
 precondition(controller.menu === menu && menu.items[0].view === row && controller.activation.superview === row)
}
precondition(changes == 4 && !active)
controller.changeActivation()
precondition(changes == 4)
// Simulate failed activation (e.g. a denied permission or unavailable trackpad).
let rejected=StatusMenu(isActive:{false},setActive:{_ in},openSettings:{},quit:{})
rejected.activation.state = .on;rejected.changeActivation()
precondition(rejected.activation.state == .off && rejected.activation.superview != nil)
active=true;controller.menuWillOpen(menu);precondition(controller.activation.state == .on)
active=false;controller.refresh();precondition(controller.activation.state == .off)
print("Menu: MagDot layout/separators, stable switch through state changes, failed activation reset, and external-state sync passed")
