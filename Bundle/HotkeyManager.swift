import Carbon

// Shared callback bridging Swift concurrency to the Carbon C event handler.
// nonisolated(unsafe) is intentional — Carbon events fire on the main thread,
// and we dispatch back to main explicitly below.
nonisolated(unsafe) private var _hotkeyFire: (() -> Void)?

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // Retrieval hotkey: ⌘⌥B
    // To remap: change hotKeyCode (Carbon virtual key) and hotKeyModifiers.
    private static let hotKeyCode: UInt32 = UInt32(kVK_ANSI_B)
    private static let hotKeyModifiers: UInt32 = UInt32(cmdKey | optionKey)

    init(onFire: @escaping () -> Void) {
        _hotkeyFire = onFire
        register()
    }

    deinit {
        unregister()
    }

    private func register() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { _hotkeyFire?() }
                return noErr
            },
            1, &spec, nil, &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x424E444C), id: 1)
        RegisterEventHotKey(
            HotkeyManager.hotKeyCode,
            HotkeyManager.hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }
}
