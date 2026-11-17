import AppKit
import CoreText

let font = CTFontCreateWithName("Wingdings2" as CFString, 64, nil)
let glyph = CTFontGetGlyphWithName(font, "penballpoint" as CFString)
guard glyph != 0, let path = CTFontCreatePathForGlyph(font, glyph, nil) else { fatalError("Wingdings 2 ballpoint pen glyph is unavailable") }
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
let bounds = path.boundingBoxOfPath
let scale = 52 / max(bounds.width, bounds.height)
context.translateBy(x: 32 - bounds.midX * scale, y: 32 - bounds.midY * scale)
context.scaleBy(x: scale, y: scale)
context.setFillColor(NSColor.black.cgColor)
context.addPath(path); context.fillPath()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
