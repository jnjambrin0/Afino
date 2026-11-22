// Generates Afino's app icon and menu bar glyph from the numbers below.
//
//   xcrun swift design/generate-icons.swift              the app icon and the menu bar glyph
//   xcrun swift design/generate-icons.swift --previews   …and a PNG of every icon appearance
//
// Run from the repository root. Needs Xcode (for `--previews`, the `ictool` inside Icon Composer).
// Writes:
//   PromptImprover/AppIcon.icon/                         Icon Composer document (SVG layers + icon.json)
//   PromptImprover/Assets.xcassets/ToolbarIcon.imageset/ menu bar template (vector PDF)
//   build/icon-previews/icon-<appearance>-1024.png       with --previews (sRGB; git-ignored), the
//                                                        input of design/render-doc-images.swift
//
// The concept, palette and rules are in docs/BRAND.md. If you fine-tune the Liquid Glass settings
// in Icon Composer instead, copy them back into `iconJSON()` or they are lost on the next run.
import AppKit
import CoreGraphics

// MARK: - Palette (sRGB). Hue 180–190° in OKLCH: "aquamarine".

enum Palette {
    /// Default (light) icon background, top → bottom. The system's lighting brightens the top.
    static let tileTop = "#00B89E"
    static let tileBottom = "#005E5A"
    /// Dark icon background, top → bottom.
    static let tileDarkTop = "#0A2D2B"
    static let tileDarkBottom = "#010E10"
    /// Crystal facets in the dark appearance (centre, left, right): accentMark (IC), accentMark, pressed.
    static let facetDark = (center: "#A5F3E4", left: "#6BE6D2", right: "#40C6B2")
}

// MARK: - Icon geometry (1024 × 1024 canvas, y down, no mask: the system applies it)

enum Crystal {
    static let cx = 512.0
    static let top = 170.0, bottom = 854.0      // apexes: 684 pt tall, 67 % of the canvas
    static let halfWidth = 110.0                // 220 wide
    static let shoulder = 142.0                 // apex → shoulder, vertically
    static let cornerRadius = 20.0              // outer vertices (HIG: no sharp corners)
    static let centerHalfWidth = 44.0           // the bright centre facet: the caret
    static let centerInset = 46.0               // centre facet starts this far below the apex (the ridge)
    static let centerRadius = 10.0
    /// Facet opacities over the tile (light comes from the upper left).
    static let leftOpacity = 0.82, rightOpacity = 0.52
}

typealias P = (x: Double, y: Double)
func lerp(_ a: P, _ b: P, _ t: Double) -> P { (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }
func toward(_ from: P, _ to: P, _ d: Double) -> P {
    let len = hypot(to.x - from.x, to.y - from.y)
    return lerp(from, to, min(d, len / 2.2) / len)
}
func f(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".00", with: "") }
func pt(_ p: P) -> String { "\(f(p.x)) \(f(p.y))" }

/// A closed polygon with every vertex rounded by a quadratic curve cut back `r` along both edges.
func roundedPolygon(_ v: [P], _ r: Double) -> String {
    var d = ""
    for i in v.indices {
        let prev = v[(i + v.count - 1) % v.count], cur = v[i], next = v[(i + 1) % v.count]
        let a = toward(cur, prev, r), b = toward(cur, next, r)
        d += (d.isEmpty ? "M" : " L") + pt(a) + " Q" + pt(cur) + " " + pt(b)
    }
    return d + " Z"
}

/// The two halves of the rounded silhouette, split exactly on the axis (de Casteljau at t = ½ on
/// the apex curves), so left + right tile the silhouette with one smooth apex at each end.
func silhouetteHalves() -> (left: String, right: String) {
    let c = Crystal.cx, T = Crystal.top, B = Crystal.bottom, W = Crystal.halfWidth, D = Crystal.shoulder, r = Crystal.cornerRadius
    let A: P = (c, T), Bt: P = (c, B)
    let rt: P = (c + W, T + D), rb: P = (c + W, B - D), lb: P = (c - W, B - D), lt: P = (c - W, T + D)
    // apex curves
    let aA = toward(A, lt, r), bA = toward(A, rt, r)
    let aB = toward(Bt, rb, r), bB = toward(Bt, lb, r)
    let mTop = lerp(lerp(aA, A, 0.5), lerp(A, bA, 0.5), 0.5)
    let mBot = lerp(lerp(aB, Bt, 0.5), lerp(Bt, bB, 0.5), 0.5)
    func corner(_ v: P, _ prev: P, _ next: P) -> String {
        " L" + pt(toward(v, prev, r)) + " Q" + pt(v) + " " + pt(toward(v, next, r))
    }
    var right = "M" + pt(mTop) + " Q" + pt(lerp(A, bA, 0.5)) + " " + pt(bA)
    right += corner(rt, A, rb) + corner(rb, rt, Bt)
    right += " L" + pt(aB) + " Q" + pt(lerp(aB, Bt, 0.5)) + " " + pt(mBot) + " Z"
    var left = "M" + pt(mBot) + " Q" + pt(lerp(Bt, bB, 0.5)) + " " + pt(bB)
    left += corner(lb, Bt, lt) + corner(lt, lb, A)
    left += " L" + pt(aA) + " Q" + pt(lerp(aA, A, 0.5)) + " " + pt(mTop) + " Z"
    return (left, right)
}

func centerFacet() -> String {
    let c = Crystal.cx, w = Crystal.centerHalfWidth
    let t = Crystal.top + Crystal.centerInset, b = Crystal.bottom - Crystal.centerInset
    let dc = w * Crystal.shoulder / Crystal.halfWidth   // parallel to the outer edges
    return roundedPolygon([(c, t), (c + w, t + dc), (c + w, b - dc), (c, b), (c - w, b - dc), (c - w, t + dc)], Crystal.centerRadius)
}

func svg1024(_ d: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path d="\(d)" fill="#FFFFFF"/>
    </svg>

    """
}

// MARK: - icon.json (schema as written by Icon Composer; arrays are front → back)

func srgb(_ hex: String) -> String {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return String(format: "srgb:%.5f,%.5f,%.5f,1.00000", Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255)
}

func gradient(_ top: String, _ bottom: String) -> [String: Any] {
    ["linear-gradient": [srgb(top), srgb(bottom)],
     "orientation": ["start": ["x": 0.5, "y": 0.0], "stop": ["x": 0.5, "y": 1.0]]]
}

func layer(_ name: String, _ file: String, dark: String, opacity: Double?) -> [String: Any] {
    var l: [String: Any] = [
        "name": name, "image-name": file, "glass": true,
        "fill-specializations": [["appearance": "dark", "value": ["solid": srgb(dark)]]],
    ]
    if let opacity { l["opacity"] = opacity }
    return l
}

func iconJSON() -> [String: Any] {
    [
        "fill-specializations": [
            ["value": gradient(Palette.tileTop, Palette.tileBottom)],
            ["appearance": "dark", "value": gradient(Palette.tileDarkTop, Palette.tileDarkBottom)],
        ],
        "groups": [[
            "layers": [
                layer("facet-center", "3-facet-center.svg", dark: Palette.facetDark.center, opacity: nil),
                layer("facet-left", "2-facet-left.svg", dark: Palette.facetDark.left, opacity: Crystal.leftOpacity),
                layer("facet-right", "1-facet-right.svg", dark: Palette.facetDark.right, opacity: Crystal.rightOpacity),
            ],
            // One glass object: no shadows between facets, one specular rim.
            "lighting": "combined",
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "specular": true,
            "translucency": ["enabled": true, "value": 0.25],
        ]],
        "supported-platforms": ["squares": "shared"],
    ]
}

// MARK: - Menu bar glyph (18 × 18 pt template, y down in the SVG; PDF flips)

enum Glyph {
    static let size = 18.0
    /// The crystal outline's centre line: 6.5 pt wide + 1.5 pt stroke = 8 pt, edges on whole points.
    static let outline: [P] = [(9, 2.4), (12.25, 6.3), (12.25, 11.7), (9, 15.6), (5.75, 11.7), (5.75, 6.3)]
    static let stroke = 1.5                     // SF Symbols medium at menu bar size ≈ 1.5 pt
    /// The caret inside: 2 pt wide (the app's caret), round caps.
    static let caret = (x: 8.0, y: 5.2, width: 2.0, height: 7.6)
}

/// The glyph as a vector PDF, black and alpha only: the outline converted to a filled ring, and the
/// caret inside it.
func glyphPDF(to url: URL) {
    var box = CGRect(x: 0, y: 0, width: Glyph.size, height: Glyph.size)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: 0, y: Glyph.size)
    ctx.scaleBy(x: 1, y: -1)
    let outline = CGMutablePath()
    outline.addLines(between: Glyph.outline.map { CGPoint(x: $0.x, y: $0.y) })
    outline.closeSubpath()
    let ring = outline.copy(strokingWithWidth: Glyph.stroke, lineCap: .butt, lineJoin: .round, miterLimit: 10)
    let c = Glyph.caret
    let caret = CGPath(roundedRect: CGRect(x: c.x, y: c.y, width: c.width, height: c.height), cornerWidth: 1, cornerHeight: 1, transform: nil)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(ring); ctx.fillPath()
    ctx.addPath(caret); ctx.fillPath()
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - Write

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
guard fm.fileExists(atPath: root.appendingPathComponent("PromptImprover.xcodeproj").path) else {
    print("Run from the repository root."); exit(1)
}
func write(_ text: String, _ path: String) {
    let url = root.appendingPathComponent(path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}

let halves = silhouetteHalves()
let layers = ["1-facet-right.svg": svg1024(halves.right), "2-facet-left.svg": svg1024(halves.left), "3-facet-center.svg": svg1024(centerFacet())]
for (name, content) in layers {
    write(content, "PromptImprover/AppIcon.icon/Assets/\(name)")
}
let json = try! JSONSerialization.data(withJSONObject: iconJSON(), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
write(String(data: json, encoding: .utf8)! + "\n", "PromptImprover/AppIcon.icon/icon.json")

let imageset = "PromptImprover/Assets.xcassets/ToolbarIcon.imageset"
try! fm.createDirectory(at: root.appendingPathComponent(imageset), withIntermediateDirectories: true)
glyphPDF(to: root.appendingPathComponent("\(imageset)/ToolbarIcon.pdf"))
write("""
{
  "images" : [
    {
      "filename" : "ToolbarIcon.pdf",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}

""", "\(imageset)/Contents.json")
print("Wrote AppIcon.icon and ToolbarIcon.pdf.")

// MARK: - Previews (ictool ships inside Icon Composer, in Xcode)

if CommandLine.arguments.contains("--previews") {
    let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
    let out = "build/icon-previews"
    try! fm.createDirectory(at: root.appendingPathComponent(out), withIntermediateDirectories: true)
    func run(_ tool: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; try! p.run(); p.waitUntilExit()
    }
    for rendition in ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"] {
        let png = "\(out)/icon-\(rendition.lowercased())-1024.png"
        run(ictool, ["PromptImprover/AppIcon.icon", "--export-image", "--output-file", png, "--platform", "macOS",
                     "--rendition", rendition, "--width", "1024", "--height", "1024", "--scale", "1"])
        // ictool writes Display P3; the previews are for documentation and the web.
        run("/usr/bin/sips", ["-m", "/System/Library/ColorSync/Profiles/sRGB Profile.icc", png, "--out", png])
    }
    print("Wrote previews to \(out)/ (full-bleed: the Dock shows the tile at 824/1024 with the system shadow).")
}
