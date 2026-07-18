import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalShortcutMonitor {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var shortcut: PushToTalkShortcut
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isPressed = false
    private var isFunctionKeyDown = false
    private var functionHoldTask: Task<Void, Never>?
    private let functionHoldDelayMilliseconds: Int
    private(set) var shortcutLabel: String

    init(
        shortcut: PushToTalkShortcut,
        functionHoldDelayMilliseconds: Int = 320,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.shortcut = shortcut
        self.functionHoldDelayMilliseconds = max(0, functionHoldDelayMilliseconds)
        self.shortcutLabel = shortcut.title
        self.onPress = onPress
        self.onRelease = onRelease
    }

    @discardableResult
    func start() -> Bool {
        stop()
        shortcutLabel = shortcut.title
        switch shortcut {
        case .fnHold:
            installFunctionKeyMonitors()
            return true
        case .off:
            return true
        case .optionSpace, .optionShiftSpace, .controlSpace, .commandShiftSpace:
            return registerCarbonShortcut()
        }
    }

    func configure(_ newShortcut: PushToTalkShortcut) {
        guard shortcut != newShortcut else { return }
        shortcut = newShortcut
        _ = start()
    }

    func stop() {
        functionHoldTask?.cancel()
        functionHoldTask = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        hotKeyRef = nil
        handlerRef = nil
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        if isPressed { onRelease() }
        isPressed = false
        isFunctionKeyDown = false
    }

    fileprivate func handleHotKey(kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed), !isPressed {
            isPressed = true
            onPress()
        } else if kind == UInt32(kEventHotKeyReleased), isPressed {
            isPressed = false
            onRelease()
        }
    }

    func handleFunctionFlags(_ flags: NSEvent.ModifierFlags) {
        let pressed = flags.contains(.function)
        if pressed, !isFunctionKeyDown {
            isFunctionKeyDown = true
            functionHoldTask?.cancel()
            if functionHoldDelayMilliseconds == 0 {
                activateFunctionShortcutIfStillHeld()
            } else {
                functionHoldTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: .milliseconds(self.functionHoldDelayMilliseconds))
                    guard !Task.isCancelled else { return }
                    self.activateFunctionShortcutIfStillHeld()
                }
            }
        } else if !pressed, isFunctionKeyDown {
            isFunctionKeyDown = false
            functionHoldTask?.cancel()
            functionHoldTask = nil
            if isPressed {
                isPressed = false
                onRelease()
            }
        }
    }

    private func activateFunctionShortcutIfStillHeld() {
        guard isFunctionKeyDown, !isPressed else { return }
        isPressed = true
        onPress()
    }

    private func installFunctionKeyMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFunctionFlags(event.modifierFlags) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFunctionFlags(event.modifierFlags) }
            return event
        }
    }

    private func registerCarbonShortcut() -> Bool {
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installResult = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                fuyuHotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                userData,
                &handlerRef
            )
        }
        guard installResult == noErr else { return false }

        let modifiers: UInt32
        switch shortcut {
        case .optionSpace: modifiers = UInt32(optionKey)
        case .optionShiftSpace: modifiers = UInt32(optionKey | shiftKey)
        case .controlSpace: modifiers = UInt32(controlKey)
        case .commandShiftSpace: modifiers = UInt32(cmdKey | shiftKey)
        case .fnHold, .off: return false
        }
        let hotKeyID = EventHotKeyID(signature: fuyuHotKeySignature, id: 1)
        let result = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if result != noErr {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
        }
        return result == noErr
    }
}

private let fuyuHotKeySignature: OSType = 0x4655_5955 // "FUYU"

private func fuyuHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    let kind = GetEventKind(event)
    Task { @MainActor in monitor.handleHotKey(kind: kind) }
    return noErr
}
