# Forksview Acceptance Fixture

> This fixture exercises the renderer spike requirements for Forksview.
> It is intentionally compact but covers the full GFM surface required for reading mode.

## Overview

Forksview renders *Markdown* with **native macOS appearance**. Visit [Example](https://example.com) or [Forksview on GitHub](https://github.com/mbuckingham74/forksview) for links. Emphasis, **strong**, *italic*, ***both***, ~~strikethrough~~ and `inline code` should all work.

## Lists

### Unordered

- First item
- Second item with **bold** and [link](https://example.com)
  - Nested item
  - Another nested item
- Third item

### Ordered

1. Step one
2. Step two
3. Step three with `code` and *italic*

### Task Lists

- [x] Completed task
- [ ] Open task
- [ ] Another open task with [link](https://example.com)

## Blockquote

> “Reading mode is the default. Editing is a deliberate toggle.”
>
> — Forksview product brief
>
> > Nested blockquote with **emphasis** and a [link](https://example.com).

## Fenced Code

```swift
import MarkdownUI

struct MarkdownReadingView: View {
    let markdown: String
    var body: some View {
        Markdown(markdown)
            .textSelection(.enabled)
    }
}
```

```markdown
# Heading in code block should not be parsed
- not a list inside code
```

## Table

| Feature | Required | Notes |
| --- | --- | --- |
| Headings | Yes | Duplicate headings must be stable |
| Tables | Yes | GFM pipe tables, header + rows |
| Task lists | Yes | Checkboxes |
| Local images | Yes | Relative to document |
| Remote images | Yes | NetworkImage |
| Code blocks | Yes | Fenced, language hint |

## Images

Local relative image (may not exist on disk, renderer should handle gracefully):

![Local asset](assets/local.png)

Same asset via relative path:

![Relative](./assets/local.png)

Remote image:

![Remote](https://picsum.photos/seed/forksview/600/300)

Remote with title:

![Remote with title](https://picsum.photos/seed/forksview2/400/200 "A remote image")

## Duplicate Headings

## Overview

Duplicate heading — second occurrence of “Overview”. Anchor generation must be stable (e.g., `overview` and `overview-1`).

## Overview

Third occurrence of “Overview”.

## Links and Autolinks

- External: [Apple](https://apple.com)
- Relative: [Other doc](./other.md) (should not crash)
- Autolink: <https://example.com>
- Email: <test@example.com>

## Inline Elements

Paragraph with enough text to test selection and copying. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Select this paragraph, copy it, and verify that the clipboard contains the expected plain text without Markdown artifacts. Repeat selection across multiple blocks to ensure the renderer does not break native selection.

Second paragraph for selection: The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. Forksview preserves reading position across mode changes using semantic heading anchors rather than raw pixels, so this text helps verify that long-document scrolling and text selection remain smooth.

## Thematic Break

---

## Long Document Behavior

This section is repeated with slight variation to expose obviously bad long-document behavior (jank, unbounded memory, layout thrashing). Each paragraph adds ~30 lines when repeated.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer nec odio. Praesent libero. Sed cursus ante dapibus diam. Sed nisi. Nulla quis sem at nibh elementum imperdiet. Duis sagittis ipsum. Praesent mauris. Fusce nec tellus sed augue semper porta. Mauris massa.

- Item A in repeated block
- Item B
- Item C with code `example`

> Blockquote in repeated block

| col1 | col2 |
| --- | --- |
| a | b |

```swift
let x = 42
```

### Repeated Block 1

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 2

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 3

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 4

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 5

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 6

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 7

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 8

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 9

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 10

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 11

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 12

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 13

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 14

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

### Repeated Block 15

Lorem ipsum dolor sit amet. Paragraph to test long scrolling. Selection should remain responsive near the bottom after many blocks. Links like [Example](https://example.com) should remain clickable even deep in the document.

## Final Heading

End of fixture. If this renders with correct headings, lists, code, tables, task lists, both image types, and remains smooth to scroll/select, the renderer passes the spike.
