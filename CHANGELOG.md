# Changelog

## 0.4

- Add optional streaming for rewrite and translation, enabled by default for new API setups. Collect output until completion, reject interrupted/truncated streams, and retain Cancel API Request. Allow 10-minute inactivity and one-hour resource timeouts.
- Simplify API Settings, move shortcut hints to the top, and remember the streaming choice.
- Keep long AI output within the writing window, soft-wrap generated prose, preserve symmetric side margins, and constrain window resizing to the usable screen.
- Paste HTML source into TXT to create a detached HTML draft and show its rendered page. View → HTML Source reveals the markup; existing TXT files are preserved.
- Add Format → Options → Pretty-print Source: a read-only, offline preview for HTML (including JS/CSS), JavaScript and JSON using bundled Prettier, with a 2 MB preview limit.
- Move Don't Hide Image Bytes in HTML to Format → Options beneath Save HTML in Dark Mode.
- Show the active document type in lowercase gray text at the upper right of the black title strip.
- Expand regression checks and update the technical report.

## 0.3

- Add Format → Resize Image with width, height, and Keep proportions enabled by default. Native and rendered HTML resizing support Undo, and saved HTML retains dimensions.
- Preserve the image type when resizing so pictures remain visible instead of turning into file icons. Resizing also repairs affected untyped attachments when their image bytes are intact.
- Brighten qlm lettering in a layered native macOS icon while retaining the black tile, shading, and rounded edges. Include a legacy icon fallback; stop replacing the native Dock icon with a flat runtime image.
- Add regression checks for rendered image pixels, preserved data, save/reopen, proportions, and undo/redo.

## 0.2

- Add File → Print (⌘P), using a temporary paginated PDF and the macOS print dialog. Native text wraps to US Letter pages independently of editor zoom. Rendered HTML uses WebKit; LaTeX uses Tectonic.
- Add Insert → Link (⌘H) for selected text, with a URL dialog, Enter/Apply, and undo. Links survive HTML save/reopen. Markdown uses link syntax; native plain text becomes an HTML draft. Hide qlm moves to ⌃⌘H.
- Prefer editable text when a slide-deck clipboard also contains an image representation. Reject image-only selections before an AI request.
- Update the technical report and release verification records.

## 0.1

Initial public release with local text and HTML editing, embedded images and supported fonts, optional API rewriting and translation, PDF/image export, and local LaTeX typesetting.
