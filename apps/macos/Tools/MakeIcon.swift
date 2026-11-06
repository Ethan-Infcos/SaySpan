import AppKit

let view = NSView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
let label = NSTextField(labelWithString: String(CommandLine.arguments[2].prefix(1)))
label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
label.textColor = .black
label.alignment = .center
label.frame = view.bounds
view.addSubview(label)
try view.dataWithPDF(inside: view.bounds).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
