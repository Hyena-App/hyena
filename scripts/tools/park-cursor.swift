// Moves the pointer to the bottom-right corner so no hover state or tooltip lands in a capture.
import CoreGraphics

let bounds = CGDisplayBounds(CGMainDisplayID())
CGWarpMouseCursorPosition(CGPoint(x: bounds.maxX - 2, y: bounds.maxY - 2))
