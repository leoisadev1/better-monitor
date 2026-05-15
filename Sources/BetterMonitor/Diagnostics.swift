import Foundation
import AppKit
import Darwin

@MainActor
struct ProcessDiagnostics {
    static func run(_ action: ProcessAction, process: ProcessSnapshot?) async -> String {
        switch action {
        case .inspect:
            guard let process else { return "No process selected." }
            return inspect(process)
        case .openFileLocation:
            guard let process else { return "No process selected." }
            return openFileLocation(process)
        case .openFilesAndPorts:
            guard let process else { return "No process selected." }
            return openFilesAndPortsText(for: process)
        case .sample:
            return await runTool("/usr/bin/sample", process: process, timeout: "3")
        case .quit:
            return await signal(process: process, signal: "TERM")
        case .forceQuit:
            return await signal(process: process, signal: "KILL")
        case .sendInterrupt:
            return await signal(process: process, signal: "INT")
        case .spindump:
            return await runTool("/usr/sbin/spindump", process: process, timeout: "3")
        case .systemDiagnostics:
            return await openDiagnosticTool("/System/Library/CoreServices/Applications/Wireless Diagnostics.app")
        case .spotlightDiagnostics:
            return await openDiagnosticTool("/System/Library/CoreServices/Applications/Spotlight.app")
        }
    }

    static func inspect(_ process: ProcessSnapshot) -> String {
        let executablePath = ProcessInfoSampler.path(pid: process.pid)
        let command = executablePath ?? process.command
        return """
        \(process.name)
        PID: \(process.pid)
        Parent PID: \(process.parentPID)
        User: \(process.user)
        Command: \(command)
        Executable Path: \(executablePath ?? "Unavailable")
        CPU: \(MonitorFormatting.percent(process.cpuPercent))
        Memory: \(MonitorFormatting.bytes(process.residentMemoryBytes))
        Threads: \(process.threadCount)
        Open Files/Ports: \(ProcessInfoSampler.openFileDescriptorCount(pid: process.pid).map(String.init) ?? "Unavailable")
        """
    }

    static func inspection(for process: ProcessSnapshot) -> ProcessInspection {
        ProcessInspection(
            pid: process.pid,
            executablePath: ProcessInfoSampler.path(pid: process.pid),
            openFileDescriptorCount: ProcessInfoSampler.openFileDescriptorCount(pid: process.pid),
            inspectedAt: Date()
        )
    }

    static func openFileLocation(_ process: ProcessSnapshot) -> String {
        guard let path = ProcessInfoSampler.path(pid: process.pid), !path.isEmpty else {
            return "Executable path is unavailable for \(process.name)."
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return "Opened file location for \(process.name)."
    }

    static func openFilesAndPorts(for process: ProcessSnapshot) -> ProcessOpenFiles {
        let text = openFilesAndPortsText(for: process)
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .prefix(80)
            .map(String.init)
        return ProcessOpenFiles(
            pid: process.pid,
            lines: lines.isEmpty ? [text] : Array(lines),
            loadedAt: Date()
        )
    }

    private static func openFilesAndPortsText(for process: ProcessSnapshot) -> String {
        do {
            let result = try Shell.run("/usr/sbin/lsof", ["-nP", "-p", "\(process.pid)"], timeout: 4)
            let text = result.output.isEmpty ? result.error : result.output
            return text.isEmpty ? "No open files or ports returned for \(process.name)." : String(text.prefix(12_000))
        } catch {
            return error.localizedDescription
        }
    }

    private static func signal(process: ProcessSnapshot?, signal: String) async -> String {
        guard let process else { return "No process selected." }
        let pid = process.pid
        if signal == "TERM",
           let application = NSRunningApplication(processIdentifier: pid),
           application.terminate() {
            return await verifiedSignalResult(process: process, signal: signal, fallbackSuccess: "Asked \(process.name) (\(pid)) to quit.")
        }
        if signal == "KILL",
           let application = NSRunningApplication(processIdentifier: pid),
           application.forceTerminate() {
            return await verifiedSignalResult(process: process, signal: signal, fallbackSuccess: "Force quit \(process.name) (\(pid)).")
        }
        do {
            let result = try Shell.run("/bin/kill", ["-\(signal)", "\(pid)"])
            if result.exitCode == 0 {
                return await verifiedSignalResult(process: process, signal: signal, fallbackSuccess: "Sent \(signal) to \(process.name) (\(pid)).")
            }
            if shouldRetryWithAdministratorPrivileges(result) {
                return await administratorSignal(process: process, signal: signal, originalError: result.error)
            }
            return result.error.isEmpty ? "kill exited with \(result.exitCode)." : result.error
        } catch {
            return error.localizedDescription
        }
    }

    private static func shouldRetryWithAdministratorPrivileges(_ result: Shell.Result) -> Bool {
        result.exitCode != 0
            && (result.error.localizedCaseInsensitiveContains("operation not permitted")
                || result.error.localizedCaseInsensitiveContains("not permitted")
                || result.error.localizedCaseInsensitiveContains("permission"))
    }

    private static func administratorSignal(process: ProcessSnapshot, signal: String, originalError: String) async -> String {
        let command = "/bin/kill -\(signal) \(process.pid)"
        let script = """
        do shell script "\(command)" with administrator privileges
        """

        do {
            let result = try Shell.run("/usr/bin/osascript", ["-e", script], timeout: 120)
            if result.exitCode == 0 {
                return await verifiedSignalResult(process: process, signal: signal, fallbackSuccess: "Sent \(signal) to \(process.name) (\(process.pid)) with administrator privileges.")
            }
            let error = result.error.isEmpty ? result.output : result.error
            return error.isEmpty ? originalError : error
        } catch {
            return error.localizedDescription
        }
    }

    private static func runTool(_ path: String, process: ProcessSnapshot?, timeout: String) async -> String {
        guard let process else { return "No process selected." }
        do {
            let result = try Shell.run(path, [String(process.pid), timeout])
            let text = result.output.isEmpty ? result.error : result.output
            return text.isEmpty ? "\(URL(fileURLWithPath: path).lastPathComponent) exited with \(result.exitCode)." : String(text.prefix(6_000))
        } catch {
            return error.localizedDescription
        }
    }

    private static func openDiagnosticTool(_ path: String) async -> String {
        let url = URL(fileURLWithPath: path)
        let didOpen = NSWorkspace.shared.open(url)
        return didOpen ? "Opened \(url.deletingPathExtension().lastPathComponent)." : "Could not open \(path)."
    }

    private static func verifiedSignalResult(process: ProcessSnapshot, signal: String, fallbackSuccess: String) async -> String {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(120))
            if !processExists(process.pid) {
                return signal == "KILL"
                    ? "Force quit \(process.name) (\(process.pid))."
                    : "Quit \(process.name) (\(process.pid))."
            }
        }
        return "\(fallbackSuccess) It is still running, so macOS or the process may be refusing the request."
    }

    private static func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
