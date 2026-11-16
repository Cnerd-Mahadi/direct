import Carbon
import Foundation

/// System-wide shortcuts through Carbon's hotkey API, which needs no Accessibility permission.
@MainActor
enum HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    /// `keyCode` is a virtual key code (kVK_*), `modifiers` Carbon flags such as `controlKey | optionKey`.
    static func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id
                MainActor.assumeIsolated { HotKey.actions[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            guard status == noErr else { return false }
            handlerInstalled = true
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4452_4354), id: id)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return false }
        actions[id] = action
        return true
    }
}
