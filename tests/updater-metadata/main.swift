import Foundation
func release(_ tag:String="v0.2.0", draft:Bool=false, prerelease:Bool=false, host:String="github.com") -> PublishedRelease {
    let prefix="https://\(host)/maxim-kich/iPhonify/releases"
    return PublishedRelease(tag_name:tag,draft:draft,prerelease:prerelease,html_url:URL(string:"\(prefix)/tag/\(tag)")!,assets:[
        .init(name:"iPhonify-\(tag)-macOS-arm64.zip",browser_download_url:URL(string:"\(prefix)/download/\(tag)/iPhonify-\(tag)-macOS-arm64.zip")!,size:1024,state:"uploaded"),
        .init(name:"appcast.xml",browser_download_url:URL(string:"\(prefix)/download/\(tag)/appcast.xml")!,size:512,state:"uploaded")])
}
precondition(release().update(current:"0.1.0") != nil)
precondition(release(draft:true).update(current:"0.1.0") == nil)
precondition(release(prerelease:true).update(current:"0.1.0") == nil)
precondition(release(host:"example.com").update(current:"0.1.0") == nil)
precondition(release().update(current:"0.2.0") == nil)
precondition(release().update(current:"0.3.0") == nil)
precondition(ReleaseVersion("v0.2.0-rc1") == nil)
precondition(ReleaseVersion("v0.2") == nil)
print("Update metadata: ordinary release accepted; drafts, prereleases, foreign URLs and downgrades rejected")

precondition(UpdateActivity().stopped)
precondition(!UpdateActivity(gesturesActive:true).stopped)
precondition(!UpdateActivity(transitionActive:true).stopped)
let driver=UpdateChecker(confirm:{_,_,_ in false})
precondition(driver.permitsTermination())
driver.check()
precondition(!driver.checking && driver.message.contains("not configured"))
let fixture=ReleaseUpdate(version:"0.2.0",archive:URL(string:"https://example.com/update.zip")!,length:1024,feed:URL(string:"https://example.com/feed")!)
let suite="iPhonify-test-"+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
defer { defaults.removePersistentDomain(forName:suite) }
var active=true, busy=true, installs=0, stops=0
var pending:(Bool)->Void = {_ in}
var valid:()->Bool = {false}
let consent=UpdateChecker(defaults:defaults,confirm:{_,_,_ in true})
consent.activity={UpdateActivity(gesturesActive:active,transitionActive:busy,activationIntent:active)}
consent.beforeRestart={ authorized, done in valid=authorized; pending=done }
consent.offerUpdate(fixture){precondition($0 == .install)}
consent.openUpdate()
precondition(!consent.permitsTermination())
consent.showReady(toInstallAndRelaunch:{if $0 == .install {installs += 1}})
consent.openUpdate()
precondition(consent.phase == .preparing && valid() && installs == 0)
pending(false)
precondition(consent.phase == .ready && !consent.restartAuthorized)
consent.openUpdate()
active=false;busy=false;pending(true)
precondition(installs == 1 && consent.permitsTermination())
precondition(defaults.dictionary(forKey:UpdateRelaunch.key)?["intent"] as? Bool == true)
var retries=0
consent.showInstallingUpdate(withApplicationTerminated:false,retryTerminatingApplication:{retries += 1})
consent.openUpdate();pending(true)
precondition(retries == 1 && defaults.dictionary(forKey:UpdateRelaunch.key)?["intent"] as? Bool == true)
// A failed retry must not trap an otherwise safe ordinary Quit.
consent.showInstallingUpdate(withApplicationTerminated:false,retryTerminatingApplication:{retries += 1})
consent.openUpdate()
precondition(!consent.permitsTermination() && !consent.canCancel)
pending(false)
precondition(consent.phase == .installing && consent.permitsTermination())
// Duplicate completion cannot trigger a second installation.
pending(true);precondition(retries == 1)
let cancelled=UpdateChecker(defaults:defaults,confirm:{_,_,_ in true})
cancelled.activity={UpdateActivity()}
cancelled.beforeRestart={authorized,done in valid=authorized;pending=done}
cancelled.offerUpdate(fixture){_ in};cancelled.openUpdate()
var skipped=false
cancelled.showReady(toInstallAndRelaunch:{skipped = $0 == .skip})
cancelled.openUpdate();cancelled.cancel()
precondition(!valid() && skipped && cancelled.permitsTermination())
pending(true)
precondition(!cancelled.restartAuthorized && defaults.object(forKey:UpdateRelaunch.key) == nil)
cancelled.showInstallingUpdate(withApplicationTerminated:false,retryTerminatingApplication:{fatalError("late retry")})
precondition(cancelled.phase == .idle)
let refusal=UpdateChecker(defaults:defaults,confirm:{_,_,_ in false})
refusal.offerUpdate(fixture){_ in fatalError("unapproved download")};refusal.openUpdate()
precondition(refusal.phase == .available)
// Exercise the production wait loop with deterministic fake ownership and acknowledgements.
let wait=UpdatePreparation()
var queue:[()->Void]=[], authorized=true, idle=false, result:Bool?
var clock=Date()
wait.now={clock};wait.schedule={queue.append($0)}
wait.start(authorized:{authorized},idle:{idle},stop:{stops += 1;return true},completion:{result=$0})
precondition(stops == 0 && result == nil)
queue.removeFirst()();precondition(stops == 0)
idle=true;queue.removeFirst()()
precondition(result == true && stops == 1)
idle=false;result=nil
wait.start(authorized:{authorized},idle:{idle},stop:{fatalError("stop while busy")},completion:{result=$0})
authorized=false;queue.removeFirst()();precondition(result == false)
authorized=true;result=nil
wait.start(authorized:{authorized},idle:{false},stop:{fatalError("forced cleanup")},completion:{result=$0})
clock=clock.addingTimeInterval(16);queue.removeFirst()();precondition(result == false)
wait.start(authorized:{true},idle:{true},stop:{false},completion:{result=$0});precondition(result == false)
// Receipts are scoped, expiring and consumed even when rejected.
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:root)}
let info:[String:Any]=["CFBundleIdentifier":"test.iphonify.receipt","CFBundleShortVersionString":"0.2.0"]
try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:root.appendingPathComponent("Info.plist"))
let bundle=Bundle(url:root)!
func receipt(_ intent:Bool)->[String:Any] { ["bundle":bundle.bundleIdentifier!,"source":"0.1.0","version":"0.2.0","path":bundle.bundleURL.path,"intent":intent,"expires":Date().addingTimeInterval(300).timeIntervalSince1970] }
for intent in [true,false] {
 defaults.set(receipt(intent),forKey:UpdateRelaunch.key)
 precondition(UpdateRelaunch.consume(defaults:defaults,bundle:bundle) == intent)
 precondition(UpdateRelaunch.consume(defaults:defaults,bundle:bundle) == nil)
}
for (key,value) in [("version","0.3.0" as Any),("source","0.2.0"),("path","/wrong"),("bundle","wrong"),("expires",0.0),("expires",Date().addingTimeInterval(900).timeIntervalSince1970)] {
 var invalid=receipt(true);invalid[key]=value;defaults.set(invalid,forKey:UpdateRelaunch.key)
 precondition(UpdateRelaunch.consume(defaults:defaults,bundle:bundle) == nil)
 precondition(defaults.object(forKey:UpdateRelaunch.key) == nil)
}
consent.showUpdaterError(NSError(domain:"test",code:1),acknowledgement:{})
precondition(!consent.restartAuthorized && defaults.object(forKey:UpdateRelaunch.key) == nil)
print("PASS: explicit consent; asynchronous stop; original intent across failures/retries; cancellation/late callbacks; timeout/stop failure; scoped ON/OFF receipt; installation error")
