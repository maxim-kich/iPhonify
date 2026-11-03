// SPDX-License-Identifier: GPL-3.0-only
// Settings layout adapted from MagDot by Maxim Kich (GPL-3.0-only).
import AppKit
import ApplicationServices
import ServiceManagement


func settingsCard(_ frame:NSRect)->NSBox {
 let box=NSBox(frame:frame);box.boxType = .custom;box.borderColor = .separatorColor
 box.borderWidth=0.5;box.cornerRadius=12;box.fillColor = .controlBackgroundColor
 box.contentViewMargins = .zero;return box
}
func settingsLabel(_ text:String,_ frame:NSRect,size:CGFloat=13,secondary:Bool=false)->NSTextField {
 let label=NSTextField(wrappingLabelWithString:text);label.frame=frame
 label.font = .systemFont(ofSize:size,weight:size>=16 ? .semibold:.regular)
 label.textColor=secondary ? .secondaryLabelColor:.labelColor;return label
}
// Link behavior follows MagDot: only the creator name is a link.
private final class SettingsLinkButton: NSButton {
 override func resetCursorRects(){super.resetCursorRects();addCursorRect(bounds,cursor:.pointingHand)}
}
private final class CreatorLinkField: NSTextField {
 override func resetCursorRects(){
  super.resetCursorRects()
  let text=attributedStringValue, range=(attributedStringValue.string as NSString).range(of:"Maxim Kich")
  guard range.location != NSNotFound else{return}
  let prefix=text.attributedSubstring(from:NSRange(location:0,length:range.location)).size().width
  let width=text.attributedSubstring(from:range).size().width
  addCursorRect(NSRect(x:prefix+2,y:0,width:width,height:bounds.height),cursor:.pointingHand)
 }
}
final class SettingsWindow:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
 weak var controller:App?
 let navigation=NSTableView()
 let content=NSView(frame:NSRect(x:220,y:0,width:640,height:640))
 let activation=NSSwitch()
 let loginSwitch=NSSwitch()
 let dockSwitch=NSSwitch()
 let screenStatus=NSTextField(labelWithString:"")
 let accessStatus=NSTextField(labelWithString:"")
 let screenButton=NSButton(title:"Allow…",target:nil,action:nil)
 let accessButton=NSButton(title:"Allow…",target:nil,action:nil)
 let updateButton=NSButton()
 let cancelUpdate=NSButton(title:"Cancel",target:nil,action:nil)
 let updateMessage=NSTextField(wrappingLabelWithString:"")
 var updateObserver:NSObjectProtocol?
 var selected=0
 var statusTimer:Timer?
 init(controller:App) {
  self.controller=controller
  let w=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:640),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
  w.collectionBehavior = [.managed,.primary,.fullScreenNone]
  w.title="iPhonify Settings";w.titleVisibility = .hidden;w.titlebarAppearsTransparent=true;w.isReleasedWhenClosed=false
  let toolbar=NSToolbar(identifier:"SettingsHeader");toolbar.showsBaselineSeparator=false;toolbar.allowsUserCustomization=false
  w.toolbar=toolbar;w.toolbarStyle = .unified
  super.init(window:w);w.delegate=self
  let root=w.contentView!;let frame=NSRect(x:8,y:8,width:204,height:624)
  let inner=NSView(frame:NSRect(origin:.zero,size:frame.size));let sidebar:NSView
  if #available(macOS 26.0,*) {
   let glass=NSGlassEffectView(frame:frame);glass.style = .regular;glass.cornerRadius=20;glass.contentView=inner;sidebar=glass
  } else {
   let effect=NSVisualEffectView(frame:frame);effect.material = .sidebar;effect.blendingMode = .behindWindow;effect.state = .active
   effect.wantsLayer=true;effect.layer?.cornerRadius=20;effect.layer?.masksToBounds=true;effect.addSubview(inner);sidebar=effect
  }
  root.addSubview(sidebar)
  let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:204,height:576));scroll.drawsBackground=false
  let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section"));column.width=204
  navigation.addTableColumn(column);navigation.headerView=nil;navigation.rowHeight=34;navigation.intercellSpacing=NSSize(width:0,height:4)
  navigation.style = .sourceList;navigation.backgroundColor = .clear;navigation.dataSource=self;navigation.delegate=self
  scroll.documentView=navigation;inner.addSubview(scroll)
  root.addSubview(content);root.addSubview(settingsLabel("iPhonify",NSRect(x:248,y:603,width:584,height:22)))
  activation.target=self;activation.action = #selector(toggleActive);activation.setAccessibilityLabel("Activate iPhonify")
  screenButton.target=self;screenButton.action = #selector(manageScreen)
  accessButton.target=self;accessButton.action = #selector(manageAccess)
  navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);refresh();w.center()
  updateObserver=NotificationCenter.default.addObserver(forName:UpdateChecker.changed,object:nil,queue:.main){[weak self] _ in self?.updateStatus()}
 }
 deinit { statusTimer?.invalidate(); if let updateObserver { NotificationCenter.default.removeObserver(updateObserver) } }
 required init?(coder:NSCoder){fatalError()}
 func numberOfRows(in tableView:NSTableView)->Int{2}
 func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
  let cell=NSTableCellView();let icon=NSImageView();icon.translatesAutoresizingMaskIntoConstraints=false
  icon.image=NSImage(systemSymbolName:["gearshape","info.circle"][row],accessibilityDescription:nil);icon.contentTintColor = .secondaryLabelColor
  cell.addSubview(icon)
  let text=NSTextField(labelWithString:["General","About"][row]);text.font = .systemFont(ofSize:13);text.translatesAutoresizingMaskIntoConstraints=false
  cell.addSubview(text);cell.textField=text;cell.imageView=icon
  NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:18),icon.heightAnchor.constraint(equalToConstant:18),text.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:8),text.centerYAnchor.constraint(equalTo:icon.centerYAnchor),text.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-8)])
  return cell
 }
 func tableViewSelectionDidChange(_ notification:Notification){selected=max(0,navigation.selectedRow);refresh()}
 func windowWillClose(_ notification:Notification){statusTimer?.invalidate();statusTimer=nil}
 func present(){
  showWindow(nil);NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil);updateStatus()
  if statusTimer == nil {statusTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in self?.updateStatus()}}
 }
 func updateStatus(){
  let login:NSControl.StateValue=SMAppService.mainApp.status == .enabled ? .on:.off
  let dock:NSControl.StateValue=(UserDefaults.standard.object(forKey:"hideFromDock") as? Bool ?? true) ? .on:.off
  let active:NSControl.StateValue=controller?.armed == true ? .on:.off
  if loginSwitch.state != login {loginSwitch.state=login}
  if dockSwitch.state != dock {dockSwitch.state=dock}
  if activation.state != active {activation.state=active}
  screenButton.title=controller?.screenAuthorizationInFlight == true ? "Requesting…" : "Allow…"
  screenButton.isEnabled = controller?.screenAuthorizationInFlight != true
  accessButton.title="Allow…"
  let screen=CGPreflightScreenCaptureAccess(),access=AXIsProcessTrusted()
  screenStatus.stringValue="Allowed";accessStatus.stringValue="Allowed"
  screenStatus.isHidden = !screen;screenButton.isHidden=screen
  accessStatus.isHidden = !access;accessButton.isHidden=access
  activation.isEnabled = screen && access || controller?.armed == true
  updateButton.title=UpdateChecker.shared.primaryTitle;updateButton.isEnabled=UpdateChecker.shared.primaryEnabled
  cancelUpdate.isHidden = !UpdateChecker.shared.canCancel;updateMessage.stringValue=UpdateChecker.shared.message
 }
 func refresh(){
  content.subviews.forEach{$0.removeFromSuperview()}
  content.addSubview(settingsLabel(["General","About"][selected],NSRect(x:28,y:544,width:560,height:34),size:24))
  if selected == 0 {
   let control=settingsCard(NSRect(x:24,y:440,width:592,height:64));content.addSubview(control)
   control.contentView?.addSubview(settingsLabel("Activate",NSRect(x:16,y:21,width:470,height:22)))
   activation.frame=NSRect(x:528,y:20,width:40,height:24);control.contentView?.addSubview(activation)
   permissionRow("Accessibility",y:360,status:accessStatus,button:accessButton)
   permissionRow("Screen Recording",y:280,status:screenStatus,button:screenButton)
   for (index,title) in ["Launch at login","Hide from Dock"].enumerated(){
    let card=settingsCard(NSRect(x:24,y:200-index*80,width:592,height:64));content.addSubview(card)
    card.contentView?.addSubview(settingsLabel(title,NSRect(x:16,y:21,width:470,height:22)))
    let control=[loginSwitch,dockSwitch][index];control.frame=NSRect(x:528,y:20,width:40,height:24);control.target=self
    control.action=index == 0 ? #selector(toggleLogin):#selector(toggleDock);control.setAccessibilityLabel(title);card.contentView?.addSubview(control)
   }
  } else {
   let box=settingsCard(NSRect(x:24,y:150,width:592,height:378));content.addSubview(box);let c=box.contentView!
   let icon=NSImageView(frame:NSRect(x:246,y:242,width:100,height:100))
   icon.image=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap { NSImage(contentsOf:$0) }
   icon.imageScaling = .scaleProportionallyUpOrDown;c.addSubview(icon)
   let name=settingsLabel("iPhonify",NSRect(x:16,y:193,width:560,height:34),size:24);name.alignment = .center;c.addSubview(name)
   let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0"
   let versionLabel=settingsLabel("Version \(version)",NSRect(x:16,y:158,width:560,height:24),secondary:true);versionLabel.alignment = .center;c.addSubview(versionLabel)
   let tagline=settingsLabel("iPhone like gestures for your Mac",NSRect(x:16,y:118,width:560,height:24),secondary:true);tagline.alignment = .center;c.addSubview(tagline)
   updateButton.target=self;updateButton.action = #selector(checkUpdate);updateButton.bezelStyle = .rounded;updateButton.frame=NSRect(x:202,y:79,width:188,height:32);c.addSubview(updateButton)
   cancelUpdate.target=self;cancelUpdate.action = #selector(cancelDownload);cancelUpdate.bezelStyle = .rounded;cancelUpdate.frame=NSRect(x:408,y:79,width:88,height:32);c.addSubview(cancelUpdate)
   updateMessage.font = .systemFont(ofSize:11);updateMessage.textColor = .secondaryLabelColor;updateMessage.alignment = .center;updateMessage.frame=NSRect(x:24,y:43,width:544,height:32);c.addSubview(updateMessage)
   let credit=CreatorLinkField(labelWithString:"");credit.frame=NSRect(x:28,y:110,width:300,height:22);credit.isSelectable=true;credit.allowsEditingTextAttributes=true
   let attribution=NSMutableAttributedString(string:"Created by Maxim Kich",attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor])
   attribution.addAttribute(.link,value:URL(string:"https://maximkich.com")!,range:(attribution.string as NSString).range(of:"Maxim Kich"));credit.attributedStringValue=attribution;content.addSubview(credit)
   let license=SettingsLinkButton(title:"Licenses",target:self,action:#selector(openLicenses));license.isBordered=false;license.attributedTitle=NSAttributedString(string:"Licenses",attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor]);license.alignment = .right;license.frame=NSRect(x:536,y:111,width:80,height:22);content.addSubview(license)
  }
  updateStatus()
 }
 func permissionRow(_ title:String,y:Int,status:NSTextField,button:NSButton){
  let card=settingsCard(NSRect(x:24,y:y,width:592,height:64));content.addSubview(card);let c=card.contentView!
  c.addSubview(settingsLabel(title,NSRect(x:16,y:21,width:350,height:22)))
  status.frame=NSRect(x:476,y:21,width:100,height:22);status.alignment = .right;status.font = .systemFont(ofSize:13);status.textColor = .systemGreen;c.addSubview(status)
  button.frame=NSRect(x:476,y:16,width:100,height:32);button.bezelStyle = .rounded;c.addSubview(button)
 }
 func showAbout(){navigation.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);selected=1;refresh();present()}
 @objc func checkUpdate(){UpdateChecker.shared.openUpdate()}
 @objc func cancelDownload(){UpdateChecker.shared.cancel()}
 @objc func toggleLogin(){
  do {
   if loginSwitch.state == .on {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
   if SMAppService.mainApp.status == .requiresApproval {SMAppService.openSystemSettingsLoginItems()}
  } catch {let alert=NSAlert();alert.messageText="Could not change launch at login";alert.informativeText=error.localizedDescription;if let window {alert.beginSheetModal(for:window)}}
  updateStatus()
 }
 @objc func toggleDock(){
  let hidden=dockSwitch.state == .on
  if DockVisibilityController.shared.apply(hidden:hidden,window:window,userInitiated:true) {
   UserDefaults.standard.set(hidden,forKey:"hideFromDock")
  } else {updateStatus()}
 }
 @objc func manageScreen(){
  if CGPreflightScreenCaptureAccess(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
  else {controller?.requestScreenRecording()}
 }
 @objc func manageAccess(){
  if AXIsProcessTrusted(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
  else {controller?.requestAccessibility()}
 }
 @objc func toggleActive(){controller?.toggle();updateStatus()}
 @objc func openCreator(){NSWorkspace.shared.open(URL(string:"https://maximkich.com")!)}
 @objc func openReleases(){NSWorkspace.shared.open(URL(string:"https://github.com/maxim-kich/iPhonify/releases")!)}
 @objc func openLicenses(){NSWorkspace.shared.open(URL(string:"https://github.com/maxim-kich/iPhonify/blob/main/ACKNOWLEDGEMENTS.md")!)}
}
