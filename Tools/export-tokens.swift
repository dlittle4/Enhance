#!/usr/bin/env swift

// Extracts the design tokens from Design/*.swift and prints them as JSON.
//
// Swift is the source of truth; the Figma file is derived. This script is the
// one-directional bridge — its output is fed back into the Figma variables so the two
// cannot drift. See DESIGN_SYSTEM.md → "Keeping Figma in sync".
//
// Why parse rather than link: this runs as a plain script with no app target, so it
// cannot import Enhance and read `Color.surfaceRaised` directly. Parsing the literal is
// less elegant but it means the script has no build dependency and cannot be broken by
// an unrelated compile error. The trade is that a token written in an unexpected form is
// silently missed — hence the `expected` counts below, which fail loudly instead.
//
// Usage:  swift Tools/export-tokens.swift            → JSON on stdout
//         swift Tools/export-tokens.swift --check    → exit 1 if a count is off

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Enhance/Design")

func read(_ name: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
}

func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return re.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }
}

struct Token: Encodable {
    let name: String
    let kind: String
    let value: String
    let detail: String?
}

var tokens: [Token] = []
var problems: [String] = []

// MARK: - Colours

let colours = try read("Colors.swift")

// `static let name = Color(hex: 0xRRGGBB)`
for m in matches(#"static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)"#, in: colours) {
    tokens.append(Token(name: m[1], kind: "color", value: "#" + m[2].uppercased(), detail: nil))
}

// `static let name = Color(red: r, green: g, blue: b)` — literals or `n / 255`
for m in matches(#"static let (\w+) = Color\(red: ([\d./ ]+), green: ([\d./ ]+), blue: ([\d./ ]+)\)"#, in: colours) {
    func channel(_ raw: String) -> Int {
        let parts = raw.split(separator: "/").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        let value = parts.count == 2 ? parts[0] / parts[1] : (parts.first ?? 0)
        return Int((value * 255).rounded())
    }
    let hex = String(format: "#%02X%02X%02X", channel(m[2]), channel(m[3]), channel(m[4]))
    tokens.append(Token(name: m[1], kind: "color", value: hex, detail: nil))
}

// `static let name = Color.white.opacity(x)`
for m in matches(#"static let (\w+) = Color\.white\.opacity\(([\d.]+)\)"#, in: colours) {
    tokens.append(Token(name: m[1], kind: "color", value: "#FFFFFF", detail: "alpha \(m[2])"))
}

// `static let name = Color.white` — a bare system colour, no constructor.
// Added when `textPrimary` landed and the counts below caught it going missing: none of the
// patterns above match a plain `Color.white`, so it exported as nothing at all.
for m in matches(#"static let (\w+) = Color\.white\n"#, in: colours) {
    tokens.append(Token(name: m[1], kind: "color", value: "#FFFFFF", detail: nil))
}

// MARK: - Radius

let constants = try read("Constants.swift")
if let block = constants.range(of: #"enum CornerRadius \{[\s\S]*?\n    \}"#, options: .regularExpression) {
    for m in matches(#"static let (\w+): CGFloat = ([\d.]+)"#, in: String(constants[block])) {
        tokens.append(Token(name: "radius/" + m[1], kind: "radius", value: m[2], detail: nil))
    }
}
for m in matches(#"static let (panelCornerRadius): CGFloat = ([\d.]+)"#, in: constants) {
    tokens.append(Token(name: "radius/panel", kind: "radius", value: m[2], detail: m[1]))
}

// MARK: - Typography

let typography = try read("Typography.swift")
for m in matches(#"static var (\w+): Font \{ \.custom\("Silkscreen-(\w+)", size: (\d+)\) \}"#, in: typography) {
    tokens.append(Token(name: m[1], kind: "type", value: "\(m[2]) \(m[3])", detail: nil))
}

// MARK: - Motion

let motion = try read("Motion.swift")
for m in matches(#"static let (\w+) = Animation\.(\w+)\(response: ([\d.]+), dampingFraction: ([\d.]+)\)"#, in: motion) {
    tokens.append(Token(name: m[1], kind: "motion", value: "\(m[2]) \(m[3]) / \(m[4])", detail: nil))
}

// MARK: - Sanity counts
//
// A regex that stops matching returns *fewer* tokens, not an error, so the export would
// quietly shrink and the Figma sync would silently stop covering something. These floors
// turn that into a failure. Raise them when tokens are added.

// Updated 2026-08-12 when the design decisions retired editorBackground, buttonSecondary,
// badgeGreen, silkscreenControl and silkscreenControlEmphasis, and added textPrimary and
// iconInactive. Raise these when tokens are added; lower them only when one is deliberately
// retired, never to make a failure go away.
let expected: [(String, Int)] = [("color", 11), ("radius", 5), ("type", 9), ("motion", 4)]
for (kind, count) in expected {
    let found = tokens.filter { $0.kind == kind }.count
    if found < count {
        problems.append("\(kind): expected at least \(count), found \(found) — a token pattern probably changed shape")
    }
}

// MARK: - Diff against the Figma snapshot
//
// `Tools/figma-tokens.json` is a committed snapshot of the Figma file's variables and text
// styles. Diffing against a *file* rather than a live API is what lets this run headlessly —
// Figma's Variables REST API is Enterprise-gated and this project is on a Professional plan, so
// a CI job could never call it. The snapshot is refreshed by an agent with Figma access whenever
// the design file changes; between refreshes, this catches Swift drifting away from it.
//
// The trade is honest and worth stating: a stale snapshot diffs clean against a Figma file that
// has since moved. `capturedAt` is there so the staleness is visible.

if let index = CommandLine.arguments.firstIndex(of: "--diff") {
    let path = CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1]
        : "Tools/figma-tokens.json"

    struct Snapshot: Decodable {
        struct Entry: Decodable { let kind: String; let name: String; let value: String }
        let capturedAt: String
        let tokens: [Entry]
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)

    // Motion has no Figma equivalent — Figma has no native motion variable — so it is exported
    // but never diffed. Comparing it would report permanent false drift.
    let comparable = tokens.filter { $0.kind != "motion" }
    var differences: [String] = []

    for token in comparable {
        guard let match = snapshot.tokens.first(where: { $0.name == token.name && $0.kind == token.kind }) else {
            differences.append("\(token.name): in Swift (\(token.value)), missing from Figma")
            continue
        }
        if match.value != token.value {
            differences.append("\(token.name): Swift \(token.value) vs Figma \(match.value)")
        }
    }
    for entry in snapshot.tokens where !comparable.contains(where: { $0.name == entry.name && $0.kind == entry.kind }) {
        differences.append("\(entry.name): in Figma (\(entry.value)), missing from Swift")
    }

    if differences.isEmpty {
        print("OK — \(comparable.count) tokens match the Figma snapshot of \(snapshot.capturedAt)")
        exit(0)
    }
    print("Drift against the Figma snapshot of \(snapshot.capturedAt):")
    differences.sorted().forEach { print("  " + $0) }
    exit(1)
}

if CommandLine.arguments.contains("--check") {
    if problems.isEmpty {
        print("OK — \(tokens.count) tokens")
        exit(0)
    }
    problems.forEach { FileHandle.standardError.write(Data(("error: " + $0 + "\n").utf8)) }
    exit(1)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try encoder.encode(tokens), encoding: .utf8)!)
if !problems.isEmpty {
    problems.forEach { FileHandle.standardError.write(Data(("warning: " + $0 + "\n").utf8)) }
}
