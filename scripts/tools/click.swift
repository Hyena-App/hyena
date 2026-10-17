// Posts a left click at screen coordinates (points, top-left origin). Used to test UI.
import CoreGraphics
import Foundation

let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let point = CGPoint(x: x, y: y)
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
}
