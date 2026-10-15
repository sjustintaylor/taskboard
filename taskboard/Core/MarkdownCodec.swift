import AppKit
import Markdown

/// A deliberately small, loss-aware Markdown surface. Unsupported syntax stays in source mode.
@MainActor enum MarkdownCodec {
    static let listMarker = NSAttributedString.Key("TaskboardListMarker")
    static let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static var attributes: [NSAttributedString.Key: Any] { [.font: baseFont, .foregroundColor: NSColor.labelColor] }

    // Inline HTML is the CommonMark escape hatch for emphasis whose punctuation
    // boundaries cannot be expressed faithfully with asterisk delimiters.
    private static let emphasisTags = ["<strong>": "</strong>", "<em>": "</em>"]

    static func supports(_ source: String) -> Bool {
        func supported(_ node: any Markup) -> Bool {
            switch node {
            case is Markdown.Document, is Paragraph, is Markdown.Text, is Strong, is Emphasis, is SoftBreak, is LineBreak:
                break
            case let html as InlineHTML:
                guard emphasisTags[html.rawHTML] != nil || emphasisTags.values.contains(html.rawHTML) else { return false }
            case let link as Markdown.Link:
                guard link.title == nil else { return false }
            case let item as ListItem:
                guard item.checkbox == nil, item.childCount == 1, item.child(at: 0) is Paragraph else { return false }
            case is UnorderedList, is OrderedList: break
            default: return false
            }
            var tags: [String] = []
            for child in node.children {
                guard supported(child) else { return false }
                if let html = child as? InlineHTML {
                    if let closing = emphasisTags[html.rawHTML] { tags.append(closing) }
                    else if tags.popLast() != html.rawHTML { return false }
                }
            }
            return tags.isEmpty
        }
        return supported(Markdown.Document(parsing: source))
    }

    static func attributed(_ source: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        func append(_ text: String, _ attrs: [NSAttributedString.Key: Any]) { output.append(NSAttributedString(string: text, attributes: attrs)) }
        func render(_ node: any Markup, _ attrs: [NSAttributedString.Key: Any]) {
            var attrs = attrs
            if let text = node as? Markdown.Text { append(text.string, attrs); return }
            if node is SoftBreak || node is LineBreak { append("\n", attrs); return }
            if node is Strong || node is Emphasis {
                let font = attrs[.font] as? NSFont ?? baseFont
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: node is Strong ? .boldFontMask : .italicFontMask)
            }
            if let link = node as? Markdown.Link, let destination = link.destination { attrs[.link] = destination }
            if node is OrderedList || node is UnorderedList {
                for (index, item) in node.children.enumerated() {
                    if index > 0 { append("\n", attributes) }
                    let start = (node as? OrderedList).map { Int($0.startIndex) } ?? 1
                    var markerAttributes = attributes
                    markerAttributes[listMarker] = true
                    append(node is OrderedList ? "\(start + index). " : "• ", markerAttributes)
                    for paragraph in item.children { render(paragraph, attrs) }
                }
                return
            }
            var stack: [[NSAttributedString.Key: Any]] = []
            for child in node.children {
                if let html = child as? InlineHTML {
                    if emphasisTags[html.rawHTML] != nil {
                        stack.append(attrs)
                        let font = attrs[.font] as? NSFont ?? baseFont
                        attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: html.rawHTML == "<strong>" ? .boldFontMask : .italicFontMask)
                    } else if let previous = stack.popLast() { attrs = previous }
                } else { render(child, attrs) }
            }
        }
        let document = Markdown.Document(parsing: source)
        for (index, child) in document.children.enumerated() {
            if index > 0 { append("\n\n", attributes) }
            render(child, attributes)
        }
        return output
    }

    static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "&\\`*_{}[]<>()#+-.!|>~".contains(character) { result += "\\" }
            result.append(character)
        }
    }
    static func markdown(_ value: NSAttributedString) -> String {
        let source = serialize(value, htmlEmphasis: false)
        let rendered = attributed(source)
        // Validate the complete inline context, including adjacent formatted runs.
        // CommonMark's delimiter rules depend on both sides of each boundary.
        guard rendered.string == value.string else { return serialize(value, htmlEmphasis: true) }
        for index in 0..<value.length {
            let expected = value.attributes(at: index, effectiveRange: nil)
            let actual = rendered.attributes(at: index, effectiveRange: nil)
            let traits: (Any?) -> NSFontTraitMask = { NSFontManager.shared.traits(of: $0 as? NSFont ?? baseFont) }
            if traits(expected[.font]) != traits(actual[.font]) {
                return serialize(value, htmlEmphasis: true)
            }
        }
        return source
    }

    private static func serialize(_ value: NSAttributedString, htmlEmphasis: Bool) -> String {
        let string = value.string as NSString
        var lines: [String] = []
        var offset = 0
        for line in value.string.components(separatedBy: "\n") {
            let length = (line as NSString).length
            var prefix = "", skip = 0
            let marked = length > 0 && value.attribute(listMarker, at: offset, effectiveRange: nil) != nil
            if marked && line.hasPrefix("• ") { prefix = "- "; skip = 2 }
            else if marked, let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                prefix = String(line[range]); skip = (prefix as NSString).length
            }
            var output = prefix
            value.enumerateAttributes(in: NSRange(location: offset + skip, length: max(0, length - skip))) { attrs, range, _ in
                let raw = string.substring(with: range)
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { output += raw; return }
                let leading = String(raw.prefix(while: { $0.isWhitespace }))
                let trailing = String(raw.reversed().prefix(while: { $0.isWhitespace }).reversed())
                var text = escape(trimmed)
                let traits = NSFontManager.shared.traits(of: attrs[.font] as? NSFont ?? baseFont)
                if traits.contains(.italicFontMask) { text = htmlEmphasis ? "<em>" + text + "</em>" : "*" + text + "*" }
                if traits.contains(.boldFontMask) { text = htmlEmphasis ? "<strong>" + text + "</strong>" : "**" + text + "**" }
                if let link = attrs[.link] {
                    let destination = String(describing: link).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: "\n", with: "")
                    text = "[\(text)](<\(destination)>)"
                }
                output += leading + text + trailing
            }
            lines.append(output)
            offset += length + 1
        }
        // A visible line break inside prose must survive a Markdown round trip.
        return lines.enumerated().map { index, line in
            guard index + 1 < lines.count, !line.isEmpty, !lines[index + 1].isEmpty,
                  !line.hasPrefix("- "), line.range(of: #"^\d+\. "#, options: .regularExpression) == nil else { return line }
            return line + "  "
        }.joined(separator: "\n")
    }
}
