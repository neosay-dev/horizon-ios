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
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
            signal(sig) { number in
                // Not async-signal-safe, but the process is ending anyway: the stack is worth it.
                let text = "signal \(number) (\(String(cString: strsignal(number))))\n\n"
                    + Thread.callStackSymbols.joined(separator: "\n")
                CrashNote.write(text)
                signal(number, SIG_DFL)
                raise(number)
            }
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
