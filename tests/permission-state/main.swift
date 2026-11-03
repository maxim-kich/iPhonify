import Foundation
precondition(!PermissionState(accessibility:false,screenRecording:false).ready)
precondition(!PermissionState(accessibility:true,screenRecording:false).ready)
precondition(!PermissionState(accessibility:false,screenRecording:true).ready)
precondition(PermissionState(accessibility:true,screenRecording:true).ready)

print("Permissions: both approvals required; missing and partial approvals stay blocked")
