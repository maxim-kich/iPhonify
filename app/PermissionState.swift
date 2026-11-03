// SPDX-License-Identifier: GPL-3.0-only
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
