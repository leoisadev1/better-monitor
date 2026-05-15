import Foundation

enum Shell {
    struct Result: Equatable {
        let output: String
        let error: String
        let exitCode: Int32
    }

    static func run(_ launchPath: String, _ arguments: [String] = [], timeout: TimeInterval = 6) throws -> Result {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("better-monitor-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("better-monitor-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return Result(output: "", error: "Command timed out: \(launchPath)", exitCode: 124)
        }

        try? outputHandle.synchronize()
        try? errorHandle.synchronize()
        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        return Result(output: output, error: error, exitCode: process.terminationStatus)
    }
}
