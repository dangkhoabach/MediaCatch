import AppKit
import SwiftUI

/// A real `NSSearchField`, not a `TextField` dressed up to look like one —
/// copied from SignalBar's already-proven `native/` code. A hand-rolled
/// `TextField` never quite matches the system search field (bezel, icon
/// inset, rounding) and only gets a generic Liquid Glass backing behind
/// arbitrary content on macOS 26+, not the real search-field chrome —
/// bridging the genuine control sidesteps that entirely.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.controlSize = .large
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
