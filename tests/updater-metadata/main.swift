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

precondition(UpdateActivity(gesturesActive:false,transitionActive:false).restartBlock == nil)
precondition(UpdateActivity(gesturesActive:true,transitionActive:false).restartBlock != nil)
precondition(UpdateActivity(gesturesActive:false,transitionActive:true).restartBlock != nil)
precondition(UpdateActivity(gesturesActive:true,transitionActive:true).restartBlock != nil)
let driver=UpdateChecker(confirm:{_,_,_ in false})
precondition(driver.permitsTermination())
driver.check()
precondition(!driver.checking && driver.message.contains("not configured"))
print("Update policy: armed gestures and transitions block restart; missing signing key fails closed")

let fixture=ReleaseUpdate(version:"0.2.0",archive:URL(string:"https://github.com/maxim-kich/iPhonify/releases/download/v0.2.0/iPhonify-v0.2.0-macOS-arm64.zip")!,length:1024,feed:URL(string:"https://github.com/maxim-kich/iPhonify/releases/download/v0.2.0/appcast.xml")!)
var blocked=true
var confirmations=0
var prepared=false
let consent=UpdateChecker(confirm:{_,_,_ in confirmations += 1;return true})
consent.activity={UpdateActivity(gesturesActive:blocked,transitionActive:false)}
consent.beforeRestart={prepared=true}
var downloaded=false
consent.offerUpdate(fixture){choice in downloaded = choice == .install}
consent.openUpdate()
precondition(downloaded && confirmations == 1)
precondition(!consent.permitsTermination())
var installed=false
consent.showReady(toInstallAndRelaunch:{choice in installed = choice == .install})
consent.openUpdate()
precondition(!installed && !prepared && confirmations == 1)
blocked=false
consent.openUpdate()
precondition(installed && prepared && confirmations == 2 && consent.permitsTermination())
let cancelling=UpdateChecker(confirm:{_,_,_ in true})
var skipped=false
cancelling.offerUpdate(fixture){choice in skipped = choice == .skip}
cancelling.cancel()
precondition(skipped && cancelling.phase == .idle && cancelling.permitsTermination())
let refusal=UpdateChecker(confirm:{_,_,_ in false})
var unauthorizedDownload=false
refusal.offerUpdate(fixture){_ in unauthorizedDownload=true}
refusal.openUpdate()
precondition(!unauthorizedDownload && refusal.phase == .available)
print("Update consent: declined downloads stay blocked, ordinary quit cannot install, active gestures block restart, explicit restart authorizes install, cancellation skips")
