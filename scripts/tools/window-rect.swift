// Prints "x,y,w,h,screenWidthPoints" for the largest on-screen Hyena window.
import CoreGraphics

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Hyena" && ($0[kCGWindowLayer as String] as? Int) == 0
}
let best = windows.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let rb = b[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
if let r = best?[kCGWindowBounds as String] as? [String: Double] {
    let screen = CGDisplayBounds(CGMainDisplayID()).width
    print("\(Int(r["X"]!)),\(Int(r["Y"]!)),\(Int(r["Width"]!)),\(Int(r["Height"]!)),\(Int(screen))")
}
