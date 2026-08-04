import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.22, alpha: 1.0),
    NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.30, alpha: 1.0)
])!
let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 230, yRadius: 230)
gradient.draw(in: background, angle: -60)

let borderColor = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.75, alpha: 1.0)
borderColor.setStroke()
background.lineWidth = 18
background.stroke()

let windowRect = NSRect(x: 170, y: 170, width: 684, height: 684)
let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: 46, yRadius: 46)
NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.11, alpha: 1.0).setFill()
windowPath.fill()

let titlebarRect = NSRect(x: 170, y: 792, width: 684, height: 62)
NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.26, alpha: 1.0).setFill()
NSBezierPath(roundedRect: titlebarRect, xRadius: 46, yRadius: 46).fill()
NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.26, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 170, y: 746, width: 684, height: 46)).fill()

let dotColors = [
    NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.32, alpha: 1.0),
    NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.30, alpha: 1.0),
    NSColor(calibratedRed: 0.33, green: 0.86, blue: 0.42, alpha: 1.0)
]
for (index, color) in dotColors.enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 222 + CGFloat(index) * 66, y: 816, width: 44, height: 44)).fill()
}

let green = NSColor(calibratedRed: 0.38, green: 0.96, blue: 0.62, alpha: 1.0)
let dim = NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.85, alpha: 1.0)
let font = NSFont.monospacedSystemFont(ofSize: 64, weight: .medium)

let line1 = NSAttributedString(string: "xcodebuild clean", attributes: [
    .font: font,
    .foregroundColor: dim
])
line1.draw(at: NSPoint(x: 250, y: 700))

let line2 = NSAttributedString(string: "zip -r backup.zip", attributes: [
    .font: font,
    .foregroundColor: dim
])
line2.draw(at: NSPoint(x: 250, y: 590))

let prompt = NSAttributedString(string: "> ", attributes: [
    .font: font,
    .foregroundColor: green
])
prompt.draw(at: NSPoint(x: 250, y: 480))

let cursor = NSAttributedString(string: "_", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 64, weight: .medium),
    .foregroundColor: green
])
cursor.draw(at: NSPoint(x: 340, y: 480))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
