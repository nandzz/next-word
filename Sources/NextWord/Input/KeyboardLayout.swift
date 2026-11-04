import Carbon.HIToolbox
import CoreGraphics

enum KeyboardLayout {
    static let ansiA: CGKeyCode = 0
    static let ansiC: CGKeyCode = 8
    static let ansiV: CGKeyCode = 9

    // Shortcuts match the character of the current layout, so a fixed ANSI code for ⌘A sends ⌘Q on AZERTY.
    @MainActor
    static func keyCode(for character: Character, fallback: CGKeyCode) -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let target = String(character)
        var buffer = [UniChar](repeating: 0, count: 4)
        for code in 0..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(code),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                &buffer
            )
            if status == noErr, length > 0, String(utf16CodeUnits: buffer, count: length) == target {
                return CGKeyCode(code)
            }
        }
        return fallback
    }
}
