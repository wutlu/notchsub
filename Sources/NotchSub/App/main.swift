import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count {
    let variant = arguments.count > index + 2 ? arguments[index + 2] : ModelOption.default.variant
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        await SelfTest.run(path: arguments[index + 1], variant: variant)
        done.signal()
    }
    done.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
