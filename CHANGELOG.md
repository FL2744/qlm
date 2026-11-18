# Changelog

## 0.2

- Add File → Print (⌘P), using a temporary paginated PDF and the macOS print dialog. Native text wraps to US Letter pages independently of editor zoom. Rendered HTML uses WebKit; LaTeX uses Tectonic.
- Add Insert → Link (⌘H) for selected text, with a URL dialog, Enter/Apply, and undo. Links survive HTML save/reopen. Markdown uses link syntax; native plain text becomes an HTML draft. Hide qlm moves to ⌃⌘H.
- Prefer editable text when a slide-deck clipboard also contains an image representation. Reject image-only selections before an AI request.
- Update the technical report and release verification records.

## 0.1

Initial public release with local text and HTML editing, embedded images and supported fonts, optional API rewriting and translation, PDF/image export, and local LaTeX typesetting.
