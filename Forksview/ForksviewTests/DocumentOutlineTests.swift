import XCTest
@testable import Forksview

@MainActor
final class DocumentOutlineTests: XCTestCase {

    // 1 ATX H1-H6
    func testATXHeadingsH1ThroughH6() {
        let md = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 6)
        XCTAssertEqual(outline.map(\.level), [1,2,3,4,5,6])
        XCTAssertEqual(outline.map(\.title), ["H1","H2","H3","H4","H5","H6"])
    }

    // 2 Optional closing hashes
    func testOptionalClosingHashes() {
        let md = """
        ## Installation ##
        ### Title ###
        # Hello #
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.map(\.title), ["Installation","Title","Hello"])
        XCTAssertEqual(outline.map(\.level), [2,3,1])
    }

    // 3 spacing rules
    func testValidSpacingRules() {
        // Valid: hash, space, text
        let valid = DocumentOutlineParser.outline(from: "# Valid\n")
        XCTAssertEqual(valid.count, 1)
        XCTAssertEqual(valid.first?.title, "Valid")
        // Invalid: no space after hashes should be paragraph, not heading (CommonMark)
        let invalid = DocumentOutlineParser.outline(from: "#Invalid\n")
        XCTAssertEqual(invalid.count, 0, "heading without space should not be heading")
        let invalid2 = DocumentOutlineParser.outline(from: "##Invalid\n")
        XCTAssertEqual(invalid2.count, 0)
        // Tab is valid after hashes
        let tabValid = DocumentOutlineParser.outline(from: "#\tTabbed\n")
        XCTAssertEqual(tabValid.count, 1)
        XCTAssertEqual(tabValid.first?.title, "Tabbed")
    }

    // 4 Setext H1/H2
    func testSetextHeadings() {
        let md = """
        Title
        =====
        Subtitle
        --------
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 2)
        XCTAssertEqual(outline[0].level, 1)
        XCTAssertEqual(outline[0].title, "Title")
        XCTAssertEqual(outline[1].level, 2)
        XCTAssertEqual(outline[1].title, "Subtitle")
    }

    // 5 Emphasis
    func testEmphasisInHeading() {
        let outline = DocumentOutlineParser.outline(from: "## *Installation* guide\n")
        XCTAssertEqual(outline.count, 1)
        XCTAssertEqual(outline.first?.title, "Installation guide")
    }

    func testStrongText() {
        let outline = DocumentOutlineParser.outline(from: "## **Bold** header\n")
        XCTAssertEqual(outline.count, 1)
        XCTAssertEqual(outline.first?.title, "Bold header")
    }

    func testLinks() {
        let outline = DocumentOutlineParser.outline(from: "## [Example](https://example.com) heading\n")
        XCTAssertEqual(outline.first?.title, "Example heading")
    }

    func testInlineCode() {
        let outline = DocumentOutlineParser.outline(from: "## `code` heading\n")
        XCTAssertEqual(outline.first?.title, "code heading")
    }

    func testStrikethrough() {
        // GFM strikethrough
        let outline = DocumentOutlineParser.outline(from: "## ~~struck~~ heading\n")
        XCTAssertEqual(outline.first?.title, "struck heading")
    }

    func testPunctuation() {
        let outline = DocumentOutlineParser.outline(from: "## Hello, world! (test) — end.\n")
        XCTAssertEqual(outline.first?.title, "Hello, world! (test) — end.")
    }

    func testEmojiUnicode() {
        let outline = DocumentOutlineParser.outline(from: "## Hello 🧭 café\n")
        XCTAssertEqual(outline.first?.title, "Hello 🧭 café")
    }

    func testImageAltTextIfSupported() {
        let outline = DocumentOutlineParser.outline(from: "## ![Alt Text](image.png) heading\n")
        // alt text should be included if parser supports; otherwise at least heading not empty and contains heading
        XCTAssertEqual(outline.count, 1)
        // If alt extracted, title includes alt; if not, at least heading part remains.
        // Our parser extracts alt via children, so expect "Alt Text heading"
        XCTAssertTrue(outline.first?.title.contains("heading") == true)
        // Strong check: if alt extracted, it will be Alt Text heading
        if let title = outline.first?.title {
            XCTAssertTrue(title == "Alt Text heading" || title == "heading", "title was \(title)")
        }
    }

    func testEmptyHeadingOmitted() {
        XCTAssertEqual(DocumentOutlineParser.outline(from: "## \n").count, 0)
        XCTAssertEqual(DocumentOutlineParser.outline(from: "##    \n").count, 0)
        XCTAssertEqual(DocumentOutlineParser.outline(from: "# \n").count, 0)
    }

    func testNoHeadingDocument() {
        let outline = DocumentOutlineParser.outline(from: "Just a paragraph\n\nAnother line")
        XCTAssertEqual(outline.count, 0)
    }

    func testBacktickFencedCodeIgnored() {
        let md = """
        ```swift
        # Not a heading
        ## Also not
        ```
        # Real Heading
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        XCTAssertEqual(outline.first?.title, "Real Heading")
    }

    func testTildeFencedCodeIgnored() {
        let md = """
        ~~~
        # Not a heading
        ~~~
        ## Real
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        XCTAssertEqual(outline.first?.title, "Real")
    }

    func testDuplicateHeadingsDistinct() {
        let md = """
        ## Installation
        text
        ## Installation
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 2)
        XCTAssertEqual(outline[0].title, "Installation")
        XCTAssertEqual(outline[1].title, "Installation")
        XCTAssertEqual(outline[0].level, 2)
        XCTAssertEqual(outline[1].level, 2)
        XCTAssertNotEqual(outline[0].sourceRange.location, outline[1].sourceRange.location)
        XCTAssertNotEqual(outline[0].id, outline[1].id)
    }

    func testHeadingsInValidContainers() {
        let md = """
        > ## Quote Heading
        - ## List Heading
        """
        let outline = DocumentOutlineParser.outline(from: md)
        // Both should be extracted; cmark supports headings inside blockquote/list
        XCTAssertTrue(outline.count >= 2, "outline count \(outline.count) should include container headings")
        XCTAssertTrue(outline.contains(where: { $0.title == "Quote Heading" && $0.level == 2 }))
        XCTAssertTrue(outline.contains(where: { $0.title == "List Heading" && $0.level == 2 }))
    }

    func testUTF16RangeCorrectnessWithEmojiBeforeHeading() {
        let emojiPrefix = "🧭🧭 "
        let md = emojiPrefix + "\n\n## After Emoji\n"
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        let item = outline[0]
        let ns = md as NSString
        // Range should correctly locate "## After Emoji" line despite emoji being 2 UTF-16 units each
        let rangeString = ns.substring(with: item.sourceRange)
        XCTAssertTrue(rangeString.contains("## After Emoji"), "rangeString was \(rangeString)")
        // Ensure range location matches NSString location of that line
        let expectedLoc = ns.range(of: "## After Emoji").location
        XCTAssertEqual(item.sourceRange.location, expectedLoc)
    }

    func testCRLFSourceRangeCorrectness() {
        let md = "Line1\r\n## Heading CRLF\r\nLine2\r\n"
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        let item = outline[0]
        let ns = md as NSString
        let str = ns.substring(with: item.sourceRange)
        XCTAssertEqual(str, "## Heading CRLF")
        // Ensure it does not include CRLF
        XCTAssertFalse(str.contains("\r"))
        XCTAssertFalse(str.contains("\n"))
    }

    func testMultilineSetextRange() {
        let md = "Installation\n------------\nBody\n"
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        let item = outline[0]
        XCTAssertEqual(item.level, 2)
        let ns = md as NSString
        let str = ns.substring(with: item.sourceRange)
        // Should cover both lines
        XCTAssertTrue(str.contains("Installation"))
        XCTAssertTrue(str.contains("------------"))
        XCTAssertTrue(str.contains("\n"))
    }

    func testInsertingTextAboveChangesSourceIdentityPredictably() {
        let original = "## First\n## Second\n"
        let outline1 = DocumentOutlineParser.outline(from: original)
        XCTAssertEqual(outline1.count, 2)
        let secondLoc1 = outline1[1].sourceRange.location
        let inserted = "Intro line\n" + original
        let outline2 = DocumentOutlineParser.outline(from: inserted)
        XCTAssertEqual(outline2.count, 2)
        let secondLoc2 = outline2[1].sourceRange.location
        XCTAssertNotEqual(secondLoc1, secondLoc2)
        // Second heading's id changed because location shifted
        XCTAssertNotEqual(outline1[1].id, outline2[1].id)
        // Title remains same
        XCTAssertEqual(outline2[1].title, "Second")
    }

    func testNearestHeadingResolution() {
        let text = "# Top\n\nBody\n\n## Section One\n\nContent\n\n### Subsection\n\nMore"
        let outline = DocumentOutlineParser.outline(from: text)
        // Offset inside "More" should resolve to Subsection
        let offsetNearEnd = (text as NSString).length - 2
        let nearest = DocumentOutlineParser.nearestHeading(for: offsetNearEnd, in: outline)
        XCTAssertEqual(nearest?.title, "Subsection")
        XCTAssertEqual(nearest?.level, 3)
        // Inside Section One content
        let sectionOneRange = (text as NSString).range(of: "Content")
        let nearest2 = DocumentOutlineParser.nearestHeading(for: sectionOneRange.location, in: outline)
        XCTAssertEqual(nearest2?.title, "Section One")
        // At top should be Top
        let nearestTop = DocumentOutlineParser.nearestHeading(for: 2, in: outline)
        XCTAssertEqual(nearestTop?.title, "Top")
        // Before any heading? Use 0
        let plain = "Just plain\nno heading\n# Later\n"
        let outlinePlain = DocumentOutlineParser.outline(from: plain)
        let before = DocumentOutlineParser.nearestHeading(for: 5, in: outlinePlain)
        XCTAssertNil(before)
        let afterLater = (plain as NSString).range(of: "Later").location + 2
        let nearestLater = DocumentOutlineParser.nearestHeading(for: afterLater, in: outlinePlain)
        XCTAssertEqual(nearestLater?.title, "Later")
    }

    func testDuplicateOccurrenceResolver() {
        let md = "## Dup\n\ntext\n\n## Dup\n\n## Other\n\n## Dup\n"
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.filter{ $0.title=="Dup"}.count, 3)
        // Rendered targets in same order
        let rendered = outline.filter{ $0.title=="Dup"}.enumerated().map { idx, item in
            RenderedHeadingTarget(id: UUID(), level: item.level, plainTitle: item.title)
        } + [RenderedHeadingTarget(id: UUID(), level: 2, plainTitle: "Other")]
        // Need full rendered in source order
        var fullRendered: [RenderedHeadingTarget] = []
        for item in outline {
            fullRendered.append(RenderedHeadingTarget(id: UUID(), level: item.level, plainTitle: item.title))
        }
        // Resolve each duplicate
        let firstDup = outline[0]
        let secondDup = outline[1]
        let thirdDup = outline[3]
        let r1 = OutlineRenderedResolver.resolve(outlineItem: firstDup, outline: outline, renderedTargets: fullRendered)
        let r2 = OutlineRenderedResolver.resolve(outlineItem: secondDup, outline: outline, renderedTargets: fullRendered)
        let r3 = OutlineRenderedResolver.resolve(outlineItem: thirdDup, outline: outline, renderedTargets: fullRendered)
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertNotNil(r3)
        XCTAssertNotEqual(r1?.id, r2?.id)
        XCTAssertNotEqual(r2?.id, r3?.id)
        // Verify occurrence resolution: second dup resolves to second rendered dup
        let dupRendered = fullRendered.filter{ $0.plainTitle=="Dup"}
        XCTAssertEqual(r1?.id, dupRendered[0].id)
        XCTAssertEqual(r2?.id, dupRendered[1].id)
        XCTAssertEqual(r3?.id, dupRendered[2].id)
    }

    func testStaleNavigationRequestRejection() {
        let md1 = "## A\n## B\n"
        let outline1 = DocumentOutlineParser.outline(from: md1)
        let itemA = outline1[0]
        let anchor = DocumentAnchor(from: itemA)
        let req = DocumentNavigationRequest(anchor: anchor)
        XCTAssertFalse(OutlineRenderedResolver.isStale(request: req, outline: outline1))
        // After editing removes A
        let md2 = "## B\n"
        let outline2 = DocumentOutlineParser.outline(from: md2)
        XCTAssertTrue(OutlineRenderedResolver.isStale(request: req, outline: outline2))
    }

    func testTwoIndependentlyDerivedOutlinesDoNotShareState() {
        let md1 = "# One\n"
        let md2 = "# Two\n## Sub\n"
        let o1 = DocumentOutlineParser.outline(from: md1)
        let o2 = DocumentOutlineParser.outline(from: md2)
        XCTAssertEqual(o1.count, 1)
        XCTAssertEqual(o2.count, 2)
        // Mutating one array should not affect other (value type)
        var mutable = o1
        mutable.append(DocumentOutlineItem(level: 2, title: "Extra", sourceRange: NSRange(location: 99, length: 5)))
        XCTAssertEqual(o1.count, 1)
        XCTAssertEqual(o2.count, 2)
        // Different contents
        XCTAssertNotEqual(o1.first?.title, o2.first?.title)
    }

    func testOutlineDerivationDoesNotTouchUndoOrChangeCount() throws {
        let doc = MarkdownDocument()
        let um = try XCTUnwrap(doc.undoManager)
        doc.replaceText(with: "# Title\n\nBody")
        // Need to set up undo grouping to track dirty
        um.groupsByEvent = false
        um.beginUndoGrouping()
        // Derive outline multiple times
        let o1 = DocumentOutlineParser.outline(from: doc.text)
        let o2 = DocumentOutlineParser.outline(from: doc.text)
        XCTAssertEqual(o1, o2)
        um.endUndoGrouping()
        // Undo should still be available for the text change, and not polluted by outline derivation
        XCTAssertTrue(um.canUndo)
        // Change count should be true after replace, but outline derivation should not have cleared or added
        XCTAssertTrue(doc.isDocumentEdited)
        // Now test that outline derivation after clean state doesn't make dirty
        let cleanDoc = MarkdownDocument()
        try cleanDoc.read(from: Data("# A\n".utf8), ofType: MarkdownDocument.typeIdentifier)
        let cleanUM = try XCTUnwrap(cleanDoc.undoManager)
        XCTAssertFalse(cleanUM.canUndo)
        XCTAssertFalse(cleanDoc.isDocumentEdited)
        _ = DocumentOutlineParser.outline(from: cleanDoc.text)
        XCTAssertFalse(cleanUM.canUndo)
        XCTAssertFalse(cleanDoc.isDocumentEdited)
    }

    // Additional edge: ensure ATX with trailing spaces still parsed
    func testATXWithTrailingSpaces() {
        let outline = DocumentOutlineParser.outline(from: "##  Title   \n")
        XCTAssertEqual(outline.first?.title, "Title")
    }

    // Test that fenced code with language identifier not parsed
    func testFencedCodeWithLanguageIgnored() {
        let md = """
        ```markdown
        # Not heading
        ```
        # Yes
        """
        let outline = DocumentOutlineParser.outline(from: md)
        XCTAssertEqual(outline.count, 1)
        XCTAssertEqual(outline.first?.title, "Yes")
    }
}
