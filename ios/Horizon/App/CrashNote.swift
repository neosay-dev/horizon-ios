import Foundation

/// Native crashes (Metal, the driver, a bad pointer) end the process without a Rust panic. These
/// handlers write the signal and the stack to Documents/logs/signal.txt first. If neither this
/// file nor panic.txt appears after the game vanished, iOS killed it (memory, watchdog).
enum CrashNote {
    private static var path: [CChar] = []

    static func install() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = Array(dir.appendingPathComponent("signal.txt").path.utf8CString)

        NSSetUncaughtExceptionHandler { exception in
            let text = "Objective-C exception: \(exception.name.rawValue): \(exception.reason ?? "")\n\n"
                + exception.callStackSymbols.joined(separator: "\n")
            CrashNote.write(text)
        }
        // A stack overflow leaves no stack for the handler: it runs on a stack of its own instead
        // (the main thread's; other threads still use their own stack).
        let altSize = 256 * 1024
        var alt = stack_t(ss_sp: UnsafeMutableRawPointer.allocate(byteCount: altSize, alignment: 16),
                          ss_size: altSize, ss_flags: 0)
        sigaltstack(&alt, nil)
        let handler: @convention(c) (Int32) -> Void = { number in
            // Not async-signal-safe, but the process is ending anyway: the stack is worth it.
            let text = "signal \(number) (\(String(cString: strsignal(number))))"
                + " on thread \(Thread.isMainThread ? "main" : "other")\n\n"
                + Thread.callStackSymbols.joined(separator: "\n")
            CrashNote.write(text)
            signal(number, SIG_DFL)
            raise(number)
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
            var action = sigaction(__sigaction_u: __sigaction_u(__sa_handler: handler),
                                   sa_mask: 0, sa_flags: SA_ONSTACK)
            sigaction(sig, &action, nil)
        }
    }

    fileprivate static func write(_ text: String) {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        text.utf8CString.withUnsafeBufferPointer { buf in
            _ = Darwin.write(fd, buf.baseAddress, max(buf.count - 1, 0))
        }
        close(fd)
    }
}
