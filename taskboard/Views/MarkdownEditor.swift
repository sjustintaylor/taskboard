import SwiftUI
import AppKit

@MainActor @Observable final class RichEditorController {
    weak var view: RichTextView?
    func trait(_ trait: NSFontTraitMask) {
        guard let view else { return }
        let range = view.selectedRange()
        if range.length == 0 {
            let font = view.typingAttributes[.font] as? NSFont ?? MarkdownCodec.baseFont
            let manager = NSFontManager.shared
            view.typingAttributes[.font] = manager.traits(of: font).contains(trait)
                ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            view.window?.makeFirstResponder(view)
            return
        }
        mutate { storage, range in
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                let font = value as? NSFont ?? MarkdownCodec.baseFont
                let manager = NSFontManager.shared
                storage.addAttribute(.font, value: manager.traits(of: font).contains(trait)
                    ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: run)
            }
        }
    }
    func link(_ destination: String) {
        mutate { storage, range in
            if destination.isEmpty { storage.removeAttribute(.link, range: range) }
            else { storage.addAttribute(.link, value: destination, range: range) }
        }
    }
    func list(ordered: Bool) {
        guard let view, let storage = view.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: view.selectedRange())
        let original = storage.attributedSubstring(from: range)
        let result = NSMutableAttributedString(string: "")
        var offset = 0
        for (index, line) in original.string.components(separatedBy: "\n").enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: MarkdownCodec.attributes)) }
            let length = (line as NSString).length
            if index > 0 && offset == original.length && length == 0 { break }
            var skip = line.hasPrefix("• ") ? 2 : 0
            if let match = line.range(of: #"^\d+\. "#, options: .regularExpression) { skip = (String(line[match]) as NSString).length }
            var markerAttributes = MarkdownCodec.attributes
            markerAttributes[MarkdownCodec.listMarker] = true
            result.append(NSAttributedString(string: ordered ? "\(index + 1). " : "• ", attributes: markerAttributes))
            result.append(original.attributedSubstring(from: NSRange(location: offset + skip, length: length - skip)))
            offset += length + 1
        }
        guard view.shouldChangeText(in: range, replacementString: result.string) else { return }
        storage.replaceCharacters(in: range, with: result)
        view.setSelectedRange(NSRange(location: range.location + result.length, length: 0))
        view.typingAttributes = MarkdownCodec.attributes
        view.didChangeText()
        view.window?.makeFirstResponder(view)
    }
    private func mutate(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let view, let storage = view.textStorage else { return }
        let range = view.selectedRange()
        guard range.length > 0, view.shouldChangeText(in: range, replacementString: nil) else { return }
        change(storage, range)
        view.didChangeText()
        view.window?.makeFirstResponder(view)
    }
}

struct MarkdownEditor: View {
    @Binding var markdown: String
    let label: String
    @State private var sourceMode = false
    @State private var controller = RichEditorController()
    @State private var linkEditor = false
    @State private var linkDestination = ""
    private var supported: Bool { MarkdownCodec.supports(markdown) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Editing mode", selection: $sourceMode) {
                Text("Rich Text").tag(false)
                Text("Markdown").tag(true)
            }.pickerStyle(.segmented).labelsHidden().disabled(!supported)
            if !supported {
                Text("This content uses additional Markdown formatting. Edit its source to preserve it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if sourceMode || !supported {
                TextEditor(text: $markdown).font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100).accessibilityLabel(label + " Markdown")
            } else {
                HStack(spacing: 10) {
                    Button { controller.trait(.boldFontMask) } label: { Image(systemName: "bold") }.help("Bold (⌘B)")
                    Button { controller.trait(.italicFontMask) } label: { Image(systemName: "italic") }.help("Italic (⌘I)")
                    Button { linkEditor = true } label: { Image(systemName: "link") }.help("Link (⌘K)")
                        .popover(isPresented: $linkEditor) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Link selected text").font(.headline)
                                TextField("https://example.com", text: $linkDestination)
                                HStack {
                                    Button("Remove Link") { controller.link(""); linkEditor = false }
                                    Spacer()
                                    Button("Apply") { controller.link(linkDestination); linkEditor = false }.disabled(linkDestination.isEmpty)
                                }
                            }.padding().frame(width: 300)
                        }
                    Button { controller.list(ordered: false) } label: { Image(systemName: "list.bullet") }.help("Bulleted list")
                    Button { controller.list(ordered: true) } label: { Image(systemName: "list.number") }.help("Numbered list")
                }.buttonStyle(.borderless)
                NativeMarkdownEditor(markdown: $markdown, label: label, controller: controller, showLink: { linkEditor = true })
                    .frame(height: 140)
            }
        }.padding(8).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }
}

final class RichTextView: NSTextView {
    var format: ((NSFontTraitMask) -> Void)?
    var showLink: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "b": format?(.boldFontMask); return
            case "i": format?(.italicFontMask); return
            case "k": showLink?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { super.insertNewline(sender); return }
        let selection = selectedRange()
        let paragraph = (string as NSString).paragraphRange(for: selection)
        guard paragraph.length > 0,
              storage.attribute(MarkdownCodec.listMarker, at: paragraph.location, effectiveRange: nil) != nil else {
            super.insertNewline(sender); return
        }
        let text = (string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)
        var marker = "• "
        if let range = text.range(of: #"^\d+\. "#, options: .regularExpression) {
            let number = Int(text[range].dropLast(2)) ?? 0
            marker = "\(number + 1). "
        }
        if text == "• " || text.range(of: #"^\d+\. $"#, options: .regularExpression) != nil {
            insertText("", replacementRange: NSRange(location: paragraph.location, length: (text as NSString).length))
            typingAttributes = MarkdownCodec.attributes
        } else {
            let insertion = NSMutableAttributedString(string: "\n", attributes: MarkdownCodec.attributes)
            var attrs = MarkdownCodec.attributes
            attrs[MarkdownCodec.listMarker] = true
            insertion.append(NSAttributedString(string: marker, attributes: attrs))
            insertText(insertion, replacementRange: selection)
            typingAttributes = MarkdownCodec.attributes
        }
    }
    // Imported RTF/HTML can contain attributes Markdown cannot represent.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

private struct NativeMarkdownEditor: NSViewRepresentable {
    @Binding var markdown: String
    let label: String
    let controller: RichEditorController
    let showLink: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = RichTextView(frame: .zero)
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = false // All edits participate in the document's merge-aware undo manager.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 5, height: 6)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.setAccessibilityLabel(label)
        scroll.documentView = view
        controller.view = view
        view.format = { [weak controller] in controller?.trait($0) }
        view.showLink = showLink
        context.coordinator.load(markdown, into: view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? RichTextView else { return }
        controller.view = view
        view.showLink = showLink
        if context.coordinator.lastSource != markdown { context.coordinator.load(markdown, into: view) }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownEditor
        var lastSource: String?
        var loading = false
        init(_ parent: NativeMarkdownEditor) { self.parent = parent }
        func load(_ source: String, into view: NSTextView) {
            loading = true
            let selection = view.selectedRange()
            view.textStorage?.setAttributedString(MarkdownCodec.attributed(source))
            let length = (view.string as NSString).length
            let start = min(selection.location, length)
            view.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
            view.typingAttributes = MarkdownCodec.attributes
            lastSource = source
            loading = false
        }
        func textDidChange(_ notification: Notification) {
            guard !loading, let view = notification.object as? NSTextView, let storage = view.textStorage else { return }
            let source = MarkdownCodec.markdown(storage)
            lastSource = source
            parent.markdown = source
        }
    }
}
