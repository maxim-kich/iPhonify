// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"iPhonify",platforms:[.macOS(.v14)],targets:[
 .target(name:"TouchBridge",path:"src/TouchBridge",publicHeadersPath:"include"),
 .executableTarget(name:"iPhonify",dependencies:["TouchBridge"],path:"app")
])
