// SPDX-License-Identifier: GPL-3.0-only
// Adapted from MagDot PR #8 by Maxim Kich (GPL-3.0-only).
import AppKit
import Carbon

// Own Dock policy transitions independently of window presentation.
final class DockVisibilityController {
    static let shared=DockVisibilityController()
    private(set) var transitioning=false
    private var queued:Bool?
    private weak var protectedWindow:NSWindow?
    private weak var pendingFocusWindow:NSWindow?
    private var originalCanHide:Bool?
    private var observers=[NSObjectProtocol]()
    init(){
        let center=NotificationCenter.default
        observers.append(center.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main){[weak self] _ in
            guard let self, self.transitioning, let window=self.pendingFocusWindow,
                  window.isVisible, !window.isMiniaturized, window.isOnActiveSpace else{return}
            // React to the actual policy handoff rather than guessing its duration.
            NSApp.activate()
        })
        observers.append(center.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in
            guard let self, let window=self.pendingFocusWindow else{return}
            self.pendingFocusWindow=nil
            guard window.isVisible, !window.isMiniaturized, window.isOnActiveSpace else{return}
            window.makeKey()
        })
        observers.append(center.addObserver(forName:NSApplication.willHideNotification,object:nil,queue:.main){[weak self] _ in
            guard let self, !self.transitioning else{return}
            // Explicit Hide must still work while the Dock icon is absent.
            if let value=self.originalCanHide {self.protectedWindow?.canHide=value}
        })
        observers.append(center.addObserver(forName:NSApplication.willUnhideNotification,object:nil,queue:.main){[weak self] _ in
            guard NSApp.activationPolicy() == .accessory else{return}
            self?.protectedWindow?.canHide=false
        })
    }
    deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
    @discardableResult
    func apply(hidden:Bool,window:NSWindow?=nil,userInitiated:Bool=false)->Bool {
        if transitioning {queued=hidden;return true}
        let policy:NSApplication.ActivationPolicy=hidden ? .accessory:.regular
        if let window, protectedWindow !== window {
            restoreProtection()
            protectedWindow=window;originalCanHide=window.canHide
        }
        if hidden {protectedWindow?.canHide=false}
        else {restoreProtection()}
        guard NSApp.activationPolicy() != policy else {return true}
        let keepFocus=userInitiated && window?.isKeyWindow == true && window?.isOnActiveSpace == true
        transitioning=true
        pendingFocusWindow=keepFocus ? window:nil
        var psn=ProcessSerialNumber(highLongOfPSN:0,lowLongOfPSN:UInt32(kCurrentProcess))
        let transform=hidden ? kProcessTransformToUIElementApplication:kProcessTransformToForegroundApplication
        let result=TransformProcessType(&psn,ProcessApplicationTransformState(transform))
        guard result == noErr else {
            transitioning=false;pendingFocusWindow=nil;restoreProtection()
            NSLog("Dock policy change failed: %d",result)
            return false
        }
        // macOS 14+ activation also cancels pending activation yields when the
        // app is already active. No delayed activation or window reopening.
        if keepFocus {NSApp.activate();window?.makeKey()}
        // Serialize rapid opposite requests; this is not a focus-restoration timer.
        DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in
            guard let self else{return}
            self.transitioning=false
            self.pendingFocusWindow=nil
            if let hidden=self.queued {
                self.queued=nil
                // A queued change never activates an app the user has left.
                self.apply(hidden:hidden,window:self.protectedWindow,userInitiated:NSApp.isActive && self.protectedWindow?.isKeyWindow == true)
            }
        }
        return true
    }
    private func restoreProtection(){
        if let originalCanHide {protectedWindow?.canHide=originalCanHide}
    }
}
func applyDockPreference(){
    DockVisibilityController.shared.apply(hidden:UserDefaults.standard.object(forKey:"hideFromDock") as? Bool ?? true)
}

