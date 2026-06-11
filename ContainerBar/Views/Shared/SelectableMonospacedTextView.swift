import SwiftUI
import AppKit

/// An `NSScrollView` + `NSTextView` representable that handles large text without hitting
/// Core Animation's texture-size limit. The text view is non-editable, selectable, wraps
/// to the available width (vertical scroll only), and uses the monospaced system font.
///
/// `updateNSView` guards against redundant string assignments so selection and scroll
/// position survive SwiftUI re-renders that carry the same content.
struct SelectableMonospacedTextView: NSViewRepresentable {
    /// The plain-text string to display.
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Build the text view using the standard factory helper so scroll/clip views
        // are wired up correctly by AppKit.
        let scrollView = NSTextView.scrollableTextView()

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Appearance
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false

        // Transparent background so the view inherits the window's material / color.
        textView.drawsBackground = false
        scrollView.drawsBackground = false

        // Wrap to width — no horizontal scroller needed.
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Inset matching the old `.padding(8)` in the SwiftUI version.
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Only show the vertical scroller.
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Guard avoids resetting selection / scroll position on every SwiftUI pass
        // when the underlying string has not changed.
        if textView.string != text {
            textView.string = text
        }
    }
}
