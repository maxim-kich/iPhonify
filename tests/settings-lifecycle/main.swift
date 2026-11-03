import AppKit

// Exercise production Settings with no gesture engine, permission requests or updater.
final class App:NSObject {
 var armed=false
 var screenAuthorizationInFlight=false
 func toggle(){}
 func requestScreenRecording(){}
 func requestAccessibility(){}
}
final class UpdateChecker {
 static let shared=UpdateChecker()
 static let changed=Notification.Name("FixtureUpdateChanged")
 let primaryTitle="Check for Updates…", primaryEnabled=true, canCancel=false, message=""
 func openUpdate(){}
 func cancel(){}
}
func pump(_ duration:TimeInterval) {
 let end=Date().addingTimeInterval(duration)
 while Date()<end {
  if let event=NSApp.nextEvent(matching:.any,until:min(end,Date().addingTimeInterval(0.02)),inMode:.default,dequeue:true) {NSApp.sendEvent(event)}
  NSApp.updateWindows()
 }
}
func check(_ passed:Bool,_ message:String) {
 guard passed else {fputs("FAIL: \(message)\n",stderr);exit(1)}
 print("PASS: \(message)")
}
let application=NSApplication.shared
application.setActivationPolicy(.accessory)
application.finishLaunching()
let original=UserDefaults.standard.object(forKey:"hideFromDock")
let controller=App()
let settings=SettingsWindow(controller:controller)
settings.present();application.activate();settings.window?.makeKeyAndOrderFront(nil)
func awaitUI(_ message:String,_ predicate:()->Bool) {
 let end=Date().addingTimeInterval(3)
 while !predicate() && Date()<end {pump(0.02)}
 check(predicate(),message)
}
awaitUI("Fixture has active Settings on current Space") {
 application.isActive && settings.window?.isKeyWindow == true && settings.window?.isOnActiveSpace == true
}
for hidden in [false,true,false,true] {
 pump(1.1)
 settings.dockSwitch.state=hidden ? .on:.off
 settings.toggleDock()
 var focusLostSamples=0
 let end=Date().addingTimeInterval(0.8)
 while Date()<end {
  if application.isHidden || settings.window?.isVisible != true {fputs("FAIL: Settings disappeared during transition\n",stderr);exit(1)}
  if settings.window?.isKeyWindow != true {focusLostSamples+=1}
  pump(0.005)
 }
 print("Focus lost samples: \(focusLostSamples)")
 check(application.activationPolicy() == (hidden ? .accessory:.regular),"Dock policy matches preference")
 check(settings.window?.isKeyWindow == true,"Settings has focus after transition")
}
pump(1.1)
for hidden in [false,true,false,true] {
 settings.dockSwitch.state=hidden ? .on:.off;settings.toggleDock()
}
pump(2.2)
check(application.activationPolicy() == .accessory,"Rapid toggles converge on latest preference")
check(settings.window?.isVisible == true && settings.window?.isKeyWindow == true,"Rapid toggles preserve Settings and focus")
check(settings.window?.canHide == false,"Settings protected while Dock hidden")
application.hide(nil)
awaitUI("Explicit Hide still works"){application.isHidden}
application.unhide(nil);settings.window?.makeKeyAndOrderFront(nil)
awaitUI("Settings restores after explicit Hide"){!application.isHidden && settings.window?.isVisible == true}
pump(1.1)
settings.dockSwitch.state = .off;settings.toggleDock();settings.close();pump(1.2)
check(settings.window?.isVisible == false && settings.statusTimer == nil,"Closed Settings stays closed")
settings.present();pump(1.1)
settings.dockSwitch.state = .on;settings.toggleDock();settings.window?.miniaturize(nil);pump(1.2)
check(settings.window?.isMiniaturized == true,"Minimized Settings stays minimized")
settings.close()
if let original {UserDefaults.standard.set(original,forKey:"hideFromDock")}
else {UserDefaults.standard.removeObject(forKey:"hideFromDock")}
application.setActivationPolicy(.accessory)
