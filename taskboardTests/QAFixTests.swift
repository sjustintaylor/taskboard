import AppKit
import Testing
@testable import taskboard

@MainActor struct QAFixTests {
    @Test func dependencyCyclesIncludeTransitiveEdges() {
        var project = Project()
        var a = BoardTask(id: "A"), b = BoardTask(id: "B")
        a.fields["depends_on"] = .array([.string("B")])
        b.fields["depends_on"] = .array([.string("C")])
        project.ungrouped = [a, b, BoardTask(id: "C"), BoardTask(id: "D")]
        #expect(project.wouldCreateDependencyCycle(taskID: "C", dependencyID: "A"))
        #expect(project.wouldCreateDependencyCycle(taskID: "A", dependencyID: "A"))
        #expect(!project.wouldCreateDependencyCycle(taskID: "D", dependencyID: "A"))
    }
    @Test func proportionalLayoutClampsAndExpands() {
        #expect(abs(BoardSplitLayout.boardWidth(total: 1240, ratio: 2.0 / 3.0) - 821.333) < 0.01)
        #expect(BoardSplitLayout.boardWidth(total: 860, ratio: 0.1) == 560)
        #expect(BoardSplitLayout.boardWidth(total: 860, ratio: 0.9) == 572)
        #expect(BoardSplitLayout.boardWidth(total: 1808, ratio: 0.7) == 1260)
    }
    @Test(arguments: ["# Heading", "```swift\nlet x = 1\n```", "- [ ] Checkbox", "![image](pic.png)", "> Quote", "- Outer\n  - Inner", "<b>HTML</b>", "~~strike~~"])
    func unsupportedMarkdownUsesSource(_ source: String) {
        #expect(!MarkdownCodec.supports(source))
    }
    @Test(arguments: ["Plain text", "**Bold** and *italic*", "[Link](https://example.com)", "- One\n- Two", "3. Three\n4. Four", "First\n\nSecond", "Text  \nnext line", "A \\*literal\\*", "***Both***", "1\\. Literal number", "A • literal bullet"])
    func richTextRoundTrips(_ source: String) {
        #expect(MarkdownCodec.supports(source))
        let first = MarkdownCodec.attributed(source)
        let saved = MarkdownCodec.markdown(first)
        #expect(MarkdownCodec.supports(saved))
        let second = MarkdownCodec.attributed(saved)
        #expect(first.string == second.string)
        for index in 0..<first.length {
            let a = first.attributes(at: index, effectiveRange: nil)
            let b = second.attributes(at: index, effectiveRange: nil)
            #expect(NSFontManager.shared.traits(of: a[.font] as! NSFont) == NSFontManager.shared.traits(of: b[.font] as! NSFont))
            #expect(String(describing: a[.link]) == String(describing: b[.link]))
        }
    }
    @Test(arguments: ["&copy;", "&#169;", "&#x1F642;", "A & B &amp; C", "&notAnEntity;"])
    func literalEntitiesSurviveMarkdownAndYAML(_ text: String) throws {
        let original = NSAttributedString(string: text, attributes: MarkdownCodec.attributes)
        let source = MarkdownCodec.markdown(original)
        var task = BoardTask(id: "entities")
        task.fields["description"] = .string(source)
        task.fields["acceptance_criteria"] = .array([.string(source)])
        var project = Project()
        project.ungrouped = [task]
        let restored = try #require(YAMLCodec.decode(YAMLCodec.encode(project)).task(task.id))
        #expect(MarkdownCodec.attributed(restored.text("description")).string == text)
        #expect(MarkdownCodec.attributed(restored.list("acceptance_criteria")[0]).string == text)
        // Existing escaped entities must remain literal after an edit, too.
        let existing = NSMutableAttributedString(attributedString: MarkdownCodec.attributed("&amp;copy;"))
        existing.append(NSAttributedString(string: " edited", attributes: MarkdownCodec.attributes))
        #expect(MarkdownCodec.attributed(MarkdownCodec.markdown(existing)).string == "&copy; edited")
    }

    @Test(arguments: ["foo.", ".bar", ".", "foo", "bar"])
    func punctuationAdjacentEmphasisSurvivesReload(_ selected: String) {
        for trait: NSFontTraitMask in [.boldFontMask, .italicFontMask, [.boldFontMask, .italicFontMask]] {
            let original = NSMutableAttributedString(string: "foo.bar", attributes: MarkdownCodec.attributes)
            let range = (original.string as NSString).range(of: selected)
            original.addAttribute(.font, value: NSFontManager.shared.convert(MarkdownCodec.baseFont, toHaveTrait: trait), range: range)
            assertFormattingRoundTrip(original)
        }
    }

    @Test func adjacentFormattedRunsAndLinksSurviveReload() {
        let original = NSMutableAttributedString(string: "foo.bar&copy;", attributes: MarkdownCodec.attributes)
        original.addAttribute(.font, value: NSFontManager.shared.convert(MarkdownCodec.baseFont, toHaveTrait: .boldFontMask), range: NSRange(location: 0, length: 4))
        original.addAttribute(.font, value: NSFontManager.shared.convert(MarkdownCodec.baseFont, toHaveTrait: .italicFontMask), range: NSRange(location: 4, length: 3))
        original.addAttribute(.link, value: "https://example.com/?q=&copy;", range: NSRange(location: 0, length: original.length))
        assertFormattingRoundTrip(original)
    }

    @Test(arguments: ["<strong>unclosed", "<em>wrong</strong>", "<strong onclick='x'>text</strong>"])
    func unsupportedHTMLStillUsesSource(_ source: String) {
        #expect(!MarkdownCodec.supports(source))
    }

    private func assertFormattingRoundTrip(_ original: NSAttributedString) {
        let source = MarkdownCodec.markdown(original)
        #expect(MarkdownCodec.supports(source))
        let restored = MarkdownCodec.attributed(source)
        #expect(restored.string == original.string)
        guard restored.length == original.length else { return }
        for index in 0..<original.length {
            let before = original.attributes(at: index, effectiveRange: nil)
            let after = restored.attributes(at: index, effectiveRange: nil)
            #expect(NSFontManager.shared.traits(of: before[.font] as! NSFont) == NSFontManager.shared.traits(of: after[.font] as! NSFont))
            #expect(String(describing: before[.link]) == String(describing: after[.link]))
        }
        #expect(MarkdownCodec.markdown(restored) == source)
    }

    @Test func emptyRichEditorCanStartAndContinueList() {
        let view = RichTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        view.isRichText = true
        view.typingAttributes = MarkdownCodec.attributes
        let controller = RichEditorController()
        controller.view = view
        controller.list(ordered: false)
        #expect(view.string == "• ")
        #expect(view.selectedRange().length == 0)
        view.insertText("First", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        view.insertText("Second", replacementRange: view.selectedRange())
        #expect(MarkdownCodec.markdown(view.attributedString()) == "- First\n- Second")
        view.insertNewline(nil)
        view.insertNewline(nil)
        #expect(view.string.hasSuffix("Second\n"))
    }
    @Test func richFormattingKeepsSelectionAndText() {
        let view = RichTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        view.textStorage?.setAttributedString(MarkdownCodec.attributed("Plain text"))
        let controller = RichEditorController()
        controller.view = view
        view.setSelectedRange(NSRange(location: 0, length: 5))
        controller.trait(.boldFontMask)
        #expect(MarkdownCodec.markdown(view.attributedString()) == "**Plain** text")
        #expect(view.selectedRange() == NSRange(location: 0, length: 5))
        controller.link("https://example.com")
        #expect(MarkdownCodec.markdown(view.attributedString()) == "[**Plain**](<https://example.com>) text")
    }
    @Test func criteriaRetainMultilineMarkdownAndBriefIndentation() throws {
        var project = Project()
        var task = BoardTask(id: "A")
        task.fields["acceptance_criteria"] = .array([.string("**One**\ncontinued"), .string("Two")])
        project.ungrouped = [task]
        let restored = try YAMLCodec.decode(YAMLCodec.encode(project))
        #expect(restored.task("A")?.list("acceptance_criteria") == ["**One**\ncontinued", "Two"])
        #expect(AgentBrief.make(task: task, project: project, fileURL: nil).contains("- **One**\n  continued\n- Two"))
    }
}
