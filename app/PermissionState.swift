// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

struct PermissionState {
 let accessibility: Bool
 let screenRecording: Bool
 var ready: Bool { accessibility && screenRecording }
 static var current: PermissionState {
  PermissionState(accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess())
 }
}
