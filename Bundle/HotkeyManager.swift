import AppKit
import Carbon

final class HotkeyManager {
    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventMonitor: Any?

    func register() {
        let id = EventHotKeyID(signature: OSType(0x424E444C), id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(11, UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref

        // Carbon hotkey events arrive in our own app queue as .systemDefined with subtype 6
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            if event.subtype.rawValue == 6 {
                self?.onToggle?()
            }
            return event
        }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }
}
