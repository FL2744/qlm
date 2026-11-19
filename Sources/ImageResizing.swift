import AppKit
import WebKit
import ImageIO

final class ImageSizeDialog: NSObject, NSTextFieldDelegate {
    let width: NSTextField
    let height: NSTextField
    let proportional = NSButton(checkboxWithTitle: "Keep proportions", target: nil, action: nil)
    let ratio: CGFloat
    init(size: NSSize) {
        width = NSTextField(string: String(format: "%.1f", size.width))
        height = NSTextField(string: String(format: "%.1f", size.height))
        ratio = size.width / max(1, size.height)
        super.init()
        width.delegate = self; height.delegate = self; proportional.state = .on
        width.setAccessibilityLabel("Image width"); height.setAccessibilityLabel("Image height")
    }
    func controlTextDidChange(_ notification: Notification) {
        guard proportional.state == .on, let field = notification.object as? NSTextField,
              let number = Double(field.stringValue), number.isFinite, number > 0 else { return }
        if field === width { height.stringValue = String(format: "%.1f", number / ratio) }
        else { width.stringValue = String(format: "%.1f", number * ratio) }
    }
    static func valid(_ size: NSSize) -> Bool {
        size.width.isFinite && size.height.isFinite && (1...10000).contains(size.width) && (1...10000).contains(size.height)
    }
    func run() -> NSSize? {
        let alert = NSAlert(); alert.messageText = "Resize Image"
        alert.informativeText = "Set the image dimensions at 100% zoom. The original image data is retained."
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        for (name, field) in [("Width", width), ("Height", height)] {
            field.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let label = NSTextField(labelWithString: name); label.widthAnchor.constraint(equalToConstant: 60).isActive = true
            stack.addArrangedSubview(NSStackView(views: [label, field]))
        }
        stack.addArrangedSubview(proportional)
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 110)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = width
        while alert.runModal() == .alertFirstButtonReturn {
            if let w = Double(width.stringValue), let h = Double(height.stringValue) {
                let size = NSSize(width: w, height: h)
                if Self.valid(size) { return size }
            }
            alert.informativeText = "Enter a width and height between 1 and 10,000."
        }
        return nil
    }
}

extension EditorController {
    func selectedImage() -> (NSTextAttachment, NSRange)? {
        let range = text.selectedRange()
        guard !htmlSourceView, !scroll.isHidden, range.length == 1, range.location < (text.textStorage?.length ?? 0),
              let attachment = text.textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              !(attachment is HTMLEmbedAttachment) else { return nil }
        return (attachment, range)
    }
    @objc func resizeImage(_ sender: Any?) {
        if let web = htmlPreview, !web.isHidden {
            let generation = web.editingGeneration
            web.evaluateJavaScript(Self.captureImageSelection, in: nil, in: .defaultClient) { [weak self, weak web] result in
                guard let self, let web, generation == web.editingGeneration else { return }
                guard case .success(let value) = result, let dimensions = value as? [String: Double],
                      let w = dimensions["width"], let h = dimensions["height"] else {
                    self.window?.presentError(aiError("Click the image you want to resize first.")); return
                }
                if let size = ImageSizeDialog(size: NSSize(width: w, height: h)).run() {
                    self.resizeWebImage(size, web: web, generation: generation)
                }
            }
            return
        }
        guard let (attachment, range) = selectedImage() else {
            window?.presentError(aiError("Click an image, then choose Format → Resize Image.")); return
        }
        var size = attachment.bounds.size
        if size.width <= 0 || size.height <= 0 { size = attachment.image?.size ?? NSSize(width: 480, height: 320) }
        if let desired = ImageSizeDialog(size: size).run() {
            do { try resizeNativeImage(at: range, to: desired) } catch { window?.presentError(error) }
        }
    }
    func resizeNativeImage(at range: NSRange, to size: NSSize) throws {
        guard ImageSizeDialog.valid(size), range.length == 1, NSMaxRange(range) <= (text.textStorage?.length ?? 0),
              let original = text.textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              !(original is HTMLEmbedAttachment) else { throw aiError("Select one image and enter valid dimensions.") }
        let attachment: NSTextAttachment
        if let bytes = original.contents ?? original.fileWrapper?.regularFileContents {
            guard NSImage(data: bytes) != nil, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let detectedType = CGImageSourceGetType(source) as String? else {
                throw aiError("This attachment does not contain a supported image.")
            }
            attachment = NSTextAttachment(data: bytes, ofType: detectedType)
            // A concrete image UTI prevents a generic file icon, including for older untyped attachments.
        } else if let image = original.image {
            attachment = NSTextAttachment(data: try HTMLImages.png(image), ofType: "public.png")
        } else { throw aiError("This image could not be resized.") }
        attachment.bounds = NSRect(origin: original.bounds.origin, size: size)
        // Replace rather than mutate the old attachment, so Undo retains its dimensions.
        let replacement = NSMutableAttributedString(attributedString: text.textStorage!.attributedSubstring(from: range))
        replacement.addAttribute(.attachment, value: attachment, range: NSRange(location: 0, length: 1))
        text.insertText(replacement, replacementRange: range)
        text.setSelectedRange(range)
        text.undoManager?.setActionName("Resize Image")
    }
    static let captureImageSelection = #"""
    (() => {
      let image = window.qlmSelectedImage;
      if (!image?.isConnected) {
        const s = window.getSelection();
        if (s?.rangeCount) {
          const r=s.getRangeAt(0);
          if (r.startContainer===r.endContainer && r.endOffset===r.startOffset+1)
            image=r.startContainer.childNodes[r.startOffset];
        }
      }
      if (image?.tagName !== 'IMG' || !document.body.contains(image)) return null;
      window.qlmResizeImage = image;
      const rect=image.getBoundingClientRect();
      return {width:rect.width || image.naturalWidth,height:rect.height || image.naturalHeight};
    })();
    """#
    func resizeWebImage(_ size: NSSize, web: HTMLWebView, generation: String) {
        guard ImageSizeDialog.valid(size), web.editingGeneration == generation else { return }
        let script = """
        (() => {
          const image=window.qlmResizeImage;
          if (!image?.isConnected) return false;
          const copy=image.cloneNode(true);
          copy.setAttribute('width','\(size.width)');copy.setAttribute('height','\(size.height)');
          copy.style.setProperty('width','\(size.width)px','important');
          copy.style.setProperty('height','\(size.height)px','important');
          for (const name of ['min-width','min-height']) copy.style.setProperty(name,'0','important');
          for (const name of ['max-width','max-height']) copy.style.setProperty(name,'none','important');
          document.body.focus({preventScroll:true});
          const range=document.createRange();range.selectNode(image);
          const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);
          const changed=document.execCommand('insertHTML',false,copy.outerHTML);
          window.qlmResizeImage=null;window.qlmSelectedImage=null;
          if (changed) document.body.dispatchEvent(new Event('input',{bubbles:true}));
          return changed;
        })();
        """
        web.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            if case .success(let changed) = result, changed as? Bool == true { return }
            self?.window?.presentError(aiError("The image could not be resized. Select it again and retry."))
        }
    }
}
