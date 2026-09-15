// Posts a real mouse click at a screen point, for verifying the app's UI
// from a script.
//
// Why this exists: AppleScript/System Events cannot drive this SwiftUI app.
// `click at`, `AXPress` and `select row` all report success and change
// nothing — sidebar rows never switch, buttons never fire. A CGEvent posted
// at the HID tap is an actual hardware-level click, and SwiftUI honours it.
// This is what let the retry button, duplicate-filename handling, the
// fetched-URL fix and the chapter-split toggle be checked in the running app
// rather than only in unit tests.
//
// Build once:   swiftc -O scripts/ui-click.swift -o /tmp/ui-click
// Use:          /tmp/ui-click <x> <y>
//
// Coordinates are in screen points (not pixels), origin top-left. On a Retina
// display that's the screenshot's pixel position divided by two — e.g.
// `screencapture -x shot.png`, find the control at (1460, 258) in the image,
// click at (730, 129). The app must already be frontmost.
//
// Pair with System Events for the rest: `keystroke "v" using command down`
// pastes into a field this has focused, and reading a text field's `value`
// through the accessibility tree still works fine for checking results.

import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2])
else {
    FileHandle.standardError.write(Data("usage: ui-click <x> <y>   (screen points, origin top-left)\n".utf8))
    exit(64)
}

let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

// Move first so the target sees a hover before the press, the way a real
// pointer arrives; the short gaps keep the down/up from being coalesced.
post(.mouseMoved)
usleep(150_000)
post(.leftMouseDown)
usleep(80_000)
post(.leftMouseUp)
print("clicked \(x) \(y)")
