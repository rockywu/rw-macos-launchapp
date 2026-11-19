import AppKit

let out = CommandLine.arguments[1]
for p in [16, 32, 128, 256, 512] {
    for s in [1, 2] {
        let n = p * s
        let image = NSImage(size: NSSize(width: n, height: n), flipped: false) { frame in
            let width = frame.width
            let outer = frame.insetBy(dx: width * 0.085, dy: width * 0.085)
            let plate = NSBezierPath(roundedRect: outer, xRadius: width * 0.19, yRadius: width * 0.19)
            NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.54, blue: 0.67, alpha: 1),
                       ending: NSColor(srgbRed: 0.025, green: 0.14, blue: 0.25, alpha: 1))?.draw(in: plate, angle: -65)
            NSColor.white.withAlphaComponent(0.23).setStroke()
            plate.lineWidth = width * 0.009
            plate.stroke()
            let tile = width * 0.129, pitch = width * 0.173
            for y in 0..<3 {
                for x in 0..<3 {
                    let tileRect = CGRect(x: width/2 + CGFloat(x-1)*pitch-tile/2, y: width/2 + CGFloat(y-1)*pitch-tile/2, width: tile, height: tile)
                    NSColor.white.withAlphaComponent(x == 1 && y == 1 ? 0.70 : 0.93).setFill()
                    NSBezierPath(roundedRect: tileRect, xRadius: tile * 0.25, yRadius: tile * 0.25).fill()
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG generation failed") }
        let name = "icon_\(p)x\(p)" + (s == 2 ? "@2x" : "") + ".png"
        try png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    }
}
