import XCTest
@testable import SpatialWorkspaceApp

final class AgentBriefTextTests: XCTestCase {
    func testEverySentenceLineIsItsOwnParagraph() {
        // Each source line becomes its own block now (the wall-breaker), so
        // three non-blank lines yield three paragraphs.
        let content = "First line one\nSecond sentence here\n\nThird block"
        XCTAssertEqual(AgentBriefText.blockKinds(content), ["paragraph", "paragraph", "paragraph"])
    }

    func testNarrationVsOutcomeTiers() {
        XCTAssertEqual(AgentBriefText.blockKinds("Let me check the deploy logs."), ["narration"])
        XCTAssertEqual(AgentBriefText.blockKinds("The build is clean and centered."), ["paragraph"])
    }

    func testLabelledStatusBecomesCallout() {
        XCTAssertEqual(AgentBriefText.blockKinds("Confirmed: the layout is responsive."), ["callout"])
        XCTAssertEqual(AgentBriefText.blockKinds("**Fixed:** two branding strings."), ["callout"])
        XCTAssertEqual(AgentBriefText.blockKinds("Warning: this path is untested."), ["callout"])
        XCTAssertEqual(AgentBriefText.calloutKind("Deployed: live now"), .done)
        // A colon deep in a sentence must not trip the callout heuristic.
        XCTAssertNil(AgentBriefText.calloutKind("The title uses a clamp and here's why: it scales."))
    }

    func testMarkdownTable() {
        let content = "| Target | Status |\n| --- | --- |\n| Web | done |\n| Game | pending |"
        XCTAssertEqual(AgentBriefText.blockKinds(content), ["table"])
    }

    func testBulletsHeadingsAndCodeFences() {
        let content = """
        **Summary**
        A normal paragraph line.
        - first bullet
        - second bullet
        ```
        swift build
        echo done
        ```
        Closing paragraph.
        """
        XCTAssertEqual(
            AgentBriefText.blockKinds(content),
            ["heading", "paragraph", "bullet", "bullet", "code", "paragraph"]
        )
    }

    func testInlineBoldLineIsNotAHeadingWhenItHasTrailingText() {
        // "**What changed** ..." must stay a paragraph (inline bold), not a heading.
        let content = "**What changed** in the config file"
        XCTAssertEqual(AgentBriefText.blockKinds(content), ["paragraph"])
    }

    func testHashHeading() {
        XCTAssertEqual(AgentBriefText.blockKinds("# Title\nbody"), ["heading", "paragraph"])
    }

    func testStripsEchoedPromptFromBriefOutput() {
        let prompt = "Great job on the render. Are we going to need more renders?"
        let content = "\(prompt)\n\nGlad it looks good. Here's the distinction:"
        XCTAssertEqual(
            AgentPane.strippingEchoedPrompt(from: content, prompt: prompt),
            "Glad it looks good. Here's the distinction:"
        )
    }

    func testKeepsContentWhenNoEcho() {
        let content = "Glad it looks good. Here's the distinction:"
        XCTAssertEqual(
            AgentPane.strippingEchoedPrompt(from: content, prompt: "totally different prompt"),
            content
        )
    }
}
