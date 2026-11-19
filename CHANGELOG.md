# Changelog

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
