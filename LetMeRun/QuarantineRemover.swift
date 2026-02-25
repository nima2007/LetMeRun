import Foundation

enum QuarantineStatus: Equatable {
    case quarantined
    case partial
    case clean
    case error(String)
}

struct QuarantineResult: Equatable {
    let status: QuarantineStatus
    let totalFiles: Int
    let quarantinedFiles: Int
}

struct QuarantineRemover {

    /// Recursively check the given path for com.apple.quarantine
    static func checkQuarantine(at path: String) -> QuarantineResult {
        var totalFiles = 0
        var quarantinedFiles = 0
        var hasError: String?

        let fileManager = FileManager.default

        // Always check the root path first
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDir) {
            totalFiles += 1
            if hasQuarantineXattr(at: path) {
                quarantinedFiles += 1
            }

            // If it's a directory, enumerate it recursively
            if isDir.boolValue {
                let url = URL(fileURLWithPath: path)
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        totalFiles += 1
                        if hasQuarantineXattr(at: fileURL.path) {
                            quarantinedFiles += 1
                        }
                    }
                } else {
                    hasError = "Could not read directory contents."
                }
            }
        } else {
            return QuarantineResult(status: .error("File does not exist"), totalFiles: 0, quarantinedFiles: 0)
        }

        if let error = hasError {
            return QuarantineResult(status: .error(error), totalFiles: totalFiles, quarantinedFiles: quarantinedFiles)
        }

        let status: QuarantineStatus
        if quarantinedFiles == 0 {
            status = .clean
        } else if quarantinedFiles == totalFiles {
            status = .quarantined
        } else {
            status = .partial
        }

        return QuarantineResult(status: status, totalFiles: totalFiles, quarantinedFiles: quarantinedFiles)
    }

    /// Recursively remove com.apple.quarantine from the given path
    static func removeQuarantine(at path: String) -> QuarantineResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-r", "-d", "com.apple.quarantine", path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Return a fresh check to get the new counts
                return checkQuarantine(at: path)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                if output.contains("No such xattr") {
                    return checkQuarantine(at: path)
                }
                return QuarantineResult(status: .error(output.trimmingCharacters(in: .whitespacesAndNewlines)), totalFiles: 0, quarantinedFiles: 0)
            }
        } catch {
            return QuarantineResult(status: .error(error.localizedDescription), totalFiles: 0, quarantinedFiles: 0)
        }
    }

    // Faster C-API check for individual files
    private static func hasQuarantineXattr(at path: String) -> Bool {
        let cPath = (path as NSString).fileSystemRepresentation
        let size = getxattr(cPath, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        // If size >= 0, the attribute exists
        return size >= 0
    }
}
