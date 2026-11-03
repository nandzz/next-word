import AppKit
import Testing
@testable import NextWord

private func context(
    bundleID: String? = nil,
    valueReadable: Bool = true,
    isSecureField: Bool = false
) -> TextContext {
    TextContext(
        appName: "Test",
        bundleID: bundleID,
        windowTitle: nil,
        textBeforeCursor: "",
        textAfterCursor: "",
        caretRect: nil,
        valueReadable: valueReadable,
        isSecureField: isSecureField
    )
}

struct ClipboardFallbackGateTests {
    @Test func allowedWithoutContext() {
        #expect(ClipboardContextReader.canUseFallback(for: nil, bundleID: "com.apple.TextEdit", secureInput: false))
    }

    @Test func allowedWhenValueIsUnreadable() {
        #expect(ClipboardContextReader.canUseFallback(for: context(valueReadable: false), bundleID: "com.apple.TextEdit", secureInput: false))
    }

    @Test func blockedWhenValueWasRead() {
        #expect(!ClipboardContextReader.canUseFallback(for: context(valueReadable: true), bundleID: "com.apple.TextEdit", secureInput: false))
    }

    @Test func blockedForSecureField() {
        #expect(!ClipboardContextReader.canUseFallback(for: context(valueReadable: false, isSecureField: true), bundleID: nil, secureInput: false))
    }

    @Test func blockedWhenSecureInputIsOn() {
        #expect(!ClipboardContextReader.canUseFallback(for: nil, bundleID: nil, secureInput: true))
    }

    @Test(arguments: [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm.ce",
        "com.sublimetext.4",
        "com.apple.dt.Xcode",
        "com.apple.finder",
    ])
    func blockedForTerminalsEditorsAndFinder(bundleID: String) {
        #expect(!ClipboardContextReader.canUseFallback(for: nil, bundleID: bundleID, secureInput: false))
        #expect(!ClipboardContextReader.canUseFallback(for: context(bundleID: bundleID, valueReadable: false), bundleID: nil, secureInput: false))
    }

    @Test func notBlockedForSimilarBundleIDs() {
        #expect(!ClipboardContextReader.isBlocked("com.apple.TextEdit"))
        #expect(!ClipboardContextReader.isBlocked("com.jetbrainsfake"))
    }
}

struct ClipboardSnapshotTypeTests {
    @Test func keepsTextRichTextImagesAndFileURLs() {
        let types: [NSPasteboard.PasteboardType] = [.string, .rtf, .html, .png, .tiff, .fileURL]
        #expect(ClipboardContextReader.typesToSnapshot(types) == types)
    }

    @Test func skipsFilePromises() {
        let types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
            NSPasteboard.PasteboardType("Apple files promise pasteboard type"),
        ]
        #expect(ClipboardContextReader.typesToSnapshot(types) == [.fileURL])
    }

    @Test func skipsDynamicTypesWhenDeclaredTypesExist() {
        let dynamic = NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu")
        #expect(ClipboardContextReader.typesToSnapshot([.string, dynamic]) == [.string])
    }

    @Test func keepsDynamicTypesWhenThereIsNothingElse() {
        let dynamic = NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu")
        #expect(ClipboardContextReader.typesToSnapshot([dynamic]) == [dynamic])
    }
}

struct FocusedTextReaderHelperTests {
    @Test func convertsToCocoaCoordinates() {
        let rect = FocusedTextReader.toCocoaCoordinates(CGRect(x: 10, y: 100, width: 2, height: 20), primaryScreenHeight: 1000)
        #expect(rect == CGRect(x: 10, y: 880, width: 2, height: 20))
    }

    @Test func keepsRectWithoutScreenHeight() {
        let rect = CGRect(x: 10, y: 100, width: 2, height: 20)
        #expect(FocusedTextReader.toCocoaCoordinates(rect, primaryScreenHeight: 0) == rect)
    }

    @Test func substringKeepsComposedCharacters() {
        let text = "ab😀cd" as NSString
        #expect(FocusedTextReader.substring(of: text, from: 0, to: 3) == "ab")
        #expect(FocusedTextReader.substring(of: text, from: 3, to: text.length) == "cd")
    }

    @Test func substringDropsClippedSurrogateAtWindowEdges() {
        let text = "😀ab😀" as NSString
        let clippedStart = text.substring(from: 1) as NSString
        #expect(FocusedTextReader.substring(of: clippedStart, from: 0, to: clippedStart.length, clipsStart: true) == "ab😀")
        let clippedEnd = text.substring(to: text.length - 1) as NSString
        #expect(FocusedTextReader.substring(of: clippedEnd, from: 0, to: clippedEnd.length, clipsEnd: true) == "😀ab")
    }

    @Test func substringClampsOutOfRangeBounds() {
        let text = "hello" as NSString
        #expect(FocusedTextReader.substring(of: text, from: -3, to: 99) == "hello")
        #expect(FocusedTextReader.substring(of: text, from: 4, to: 2) == "")
    }

    @Test(arguments: [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
    ])
    func detectsChromiumBrowsers(bundleID: String) {
        #expect(FocusedTextReader.detectKind(bundleID: bundleID, bundleURL: nil) == .chromiumBrowser)
    }

    @Test(arguments: ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.VSCode"])
    func detectsKnownElectronApps(bundleID: String) {
        #expect(FocusedTextReader.detectKind(bundleID: bundleID, bundleURL: nil) == .electron)
    }

    @Test func nativeAppWithoutChromiumFrameworks() {
        let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        #expect(FocusedTextReader.detectKind(bundleID: "com.apple.TextEdit", bundleURL: url) == .native)
    }
}
