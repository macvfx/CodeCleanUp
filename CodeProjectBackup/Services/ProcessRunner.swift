import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }
}

final class ProcessHandle {
    weak var process: Process?

    func terminate() {
        process?.terminate()
    }
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        environment: [String: String]? = nil,
        handle: ProcessHandle? = nil
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }
        handle?.process = process

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let outGroup = DispatchGroup()
        let errGroup = DispatchGroup()

        outGroup.enter()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outGroup.leave()
            } else {
                lock.lock()
                outData.append(data)
                lock.unlock()
            }
        }
        errGroup.enter()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                errGroup.leave()
            } else {
                lock.lock()
                errData.append(data)
                lock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "Failed to launch \(executable): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        outGroup.wait()
        errGroup.wait()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
