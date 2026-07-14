import SwiftUI
import AppKit

// 折り返しなし・横スクロール可能な編集テキストビュー
struct HScrollTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = []
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.drawsBackground = false

        // 折り返しをやめて横方向に伸ばす
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.lineFragmentPadding = 6

        tv.delegate = context.coordinator
        tv.string = text

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self   // 常に最新のBindingを使う
        guard let tv = nsView.documentView as? NSTextView else { return }
        // 日本語入力(marked text)中は同期しない — 変換が中断されるのを防ぐ
        if tv.hasMarkedText() { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            // 可能ならカーソル位置を維持
            if sel.location <= (text as NSString).length {
                tv.setSelectedRange(sel)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HScrollTextEditor
        init(_ parent: HScrollTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
