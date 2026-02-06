import Foundation

actor PythonBridge {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isRunning = false
    private var responseHandler: CheckedContinuation<[String: Any], Error>?
    private var pendingData = Data()
    private var readTask: Task<Void, Never>?

    enum BridgeError: LocalizedError {
        case pythonNotFound
        case bridgeScriptNotFound
        case processNotRunning
        case invalidResponse
        case bridgeError(String)
        case startupTimeout

        var errorDescription: String? {
            switch self {
            case .pythonNotFound:
                return "Python3 executable not found"
            case .bridgeScriptNotFound:
                return "bridge.py script not found"
            case .processNotRunning:
                return "Python bridge process is not running"
            case .invalidResponse:
                return "Invalid response from Python bridge"
            case .bridgeError(let message):
                return "Bridge error: \(message)"
            case .startupTimeout:
                return "Bridge startup timed out waiting for ready signal"
            }
        }
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        if let bundledPath = findBundledBridge() {
            // Use bundled standalone binary (no Python needed)
            print("[PythonBridge] Using bundled bridge binary: \(bundledPath)")
            proc.executableURL = URL(fileURLWithPath: bundledPath)
            proc.arguments = []
            let bridgeDir = (bundledPath as NSString).deletingLastPathComponent
            proc.currentDirectoryURL = URL(fileURLWithPath: bridgeDir)
        } else {
            // Fall back to Python + bridge.py for development
            let pythonPath = try findPython()
            let scriptPath = try findBridgeScript()
            print("[PythonBridge] Using Python bridge: \(pythonPath) \(scriptPath)")
            proc.executableURL = URL(fileURLWithPath: pythonPath)
            proc.arguments = ["-u", scriptPath]
            let scriptsDir = (scriptPath as NSString).deletingLastPathComponent
            proc.currentDirectoryURL = URL(fileURLWithPath: scriptsDir)
        }

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.pendingData = Data()

        proc.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.handleProcessTermination()
            }
        }

        try proc.run()
        isRunning = true

        startReadingStderr(pipe: stderr)
        startReadingStdout(pipe: stdout)

        // Wait for the {"type": "ready"} message from bridge.py
        try await waitForReady()
    }

    func stop() {
        readTask?.cancel()
        readTask = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning = false

        // Fail any pending continuation
        if let handler = responseHandler {
            responseHandler = nil
            handler.resume(throwing: BridgeError.processNotRunning)
        }
    }

    // MARK: - Command / Response

    func send(command: [String: Any]) async throws -> [String: Any] {
        guard isRunning, let stdinPipe = stdinPipe else {
            throw BridgeError.processNotRunning
        }

        let jsonData = try JSONSerialization.data(withJSONObject: command, options: [])
        guard var line = String(data: jsonData, encoding: .utf8) else {
            throw BridgeError.invalidResponse
        }
        line += "\n"

        let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            self.responseHandler = continuation
            if let data = line.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
        }

        // Check for error status in the response
        if let status = response["status"] as? String, status == "error" {
            let message = response["message"] as? String ?? "Unknown error"
            throw BridgeError.bridgeError(message)
        }

        return response
    }

    // MARK: - Find Bundled Bridge

    private func findBundledBridge() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []

        // 1. Inside app bundle: Contents/Resources/bridge/bridge
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("bridge/bridge").path)
        }

        // 2. Dev build: Scripts/dist/bridge/bridge relative to project root
        let projectPaths = findProjectRootCandidates()
        for root in projectPaths {
            candidates.append(root + "/Scripts/dist/bridge/bridge")
        }

        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if fileManager.isExecutableFile(atPath: resolved) {
                return resolved
            }
        }

        return nil
    }

    // MARK: - Find Python

    private func findPython() throws -> String {
        let fileManager = FileManager.default

        // Candidate paths for python3
        var candidates: [String] = []

        // 1. Virtual env relative to project/bundle
        let projectPaths = findProjectRootCandidates()
        for root in projectPaths {
            candidates.append(root + "/Scripts/.venv/bin/python3")
        }

        // 2. Common system / homebrew paths
        candidates.append(contentsOf: [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
        ])

        // 3. pyenv shim
        let home = fileManager.homeDirectoryForCurrentUser.path
        candidates.append(home + "/.pyenv/shims/python3")

        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Last resort: use /usr/bin/env python3 (lets the shell resolve it)
        let envPath = "/usr/bin/env"
        if fileManager.isExecutableFile(atPath: envPath) {
            // We'll set python3 as argument instead
            return envPath
        }

        throw BridgeError.pythonNotFound
    }

    // MARK: - Find bridge.py

    private func findBridgeScript() throws -> String {
        let fileManager = FileManager.default

        var candidates: [String] = []

        // 1. Inside app bundle resources
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Scripts/bridge.py").path)
        }

        // 2. Relative to the executable's directory (e.g., during development)
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent().path
            candidates.append(execDir + "/../Scripts/bridge.py")
        }

        // 3. Project root candidates
        let projectPaths = findProjectRootCandidates()
        for root in projectPaths {
            candidates.append(root + "/Scripts/bridge.py")
        }

        // 4. Current working directory
        let cwd = fileManager.currentDirectoryPath
        candidates.append(cwd + "/Scripts/bridge.py")

        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if fileManager.fileExists(atPath: resolved) {
                return resolved
            }
        }

        throw BridgeError.bridgeScriptNotFound
    }

    // MARK: - Project Root Candidates

    private func findProjectRootCandidates() -> [String] {
        var roots: [String] = []

        // From bundle
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.deletingLastPathComponent().path)
        }

        // From executable - walk up to find project root
        if let execURL = Bundle.main.executableURL {
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<12 {
                roots.append(dir.path)
                dir = dir.deletingLastPathComponent()
            }
        }

        // Current working directory
        roots.append(FileManager.default.currentDirectoryPath)

        // Check for .xcodeproj to identify the actual project root
        // This handles running from DerivedData where CWD may be wrong
        let fileManager = FileManager.default
        for root in Array(roots) {
            // Look for project.yml or .xcodeproj as project root markers
            let projectYml = root + "/project.yml"
            let scriptsDir = root + "/Scripts/bridge.py"
            if fileManager.fileExists(atPath: projectYml) || fileManager.fileExists(atPath: scriptsDir) {
                // Move this to the front as highest priority
                roots.insert(root, at: 0)
            }
        }

        // Also search common development directories based on the source file location
        // The Xcode project is at /Users/tutlexuan/AutoLocation
        // Use #filePath if available, otherwise try to resolve from bundle ID
        if let sourceRoot = resolveSourceRoot() {
            roots.insert(sourceRoot, at: 0)
        }

        return roots
    }

    /// Resolve the project source root by looking for the project directory
    /// based on the Xcode build settings embedded in the app bundle.
    private func resolveSourceRoot() -> String? {
        let fileManager = FileManager.default

        // Strategy 1: Check the SRCROOT via the Info.plist or known path patterns
        // When built with Xcode, the source root can be inferred from the build path
        if let execURL = Bundle.main.executableURL {
            let execPath = execURL.path
            // DerivedData path looks like: .../DerivedData/ProjectName-hash/Build/Products/Debug/App.app/Contents/MacOS/App
            // The project name in the DerivedData folder matches the Xcode project
            if let range = execPath.range(of: "/DerivedData/") {
                let afterDerived = String(execPath[range.upperBound...])
                // Extract project name (before the hash)
                if let dashRange = afterDerived.range(of: "-") {
                    let projectName = String(afterDerived[..<dashRange.lowerBound])
                    // Search common locations for the project
                    let home = fileManager.homeDirectoryForCurrentUser.path
                    let candidates = [
                        home + "/" + projectName,
                        home + "/Developer/" + projectName,
                        home + "/Projects/" + projectName,
                        home + "/Desktop/" + projectName,
                        home + "/Documents/" + projectName,
                    ]
                    for candidate in candidates {
                        if fileManager.fileExists(atPath: candidate + "/Scripts/bridge.py") {
                            return candidate
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Stdout Reading

    private func startReadingStdout(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        readTask = Task { [weak self] in
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty {
                    // EOF - process likely terminated
                    break
                }
                await self?.processStdoutData(data)
            }
        }
    }

    private func processStdoutData(_ data: Data) {
        pendingData.append(data)

        // Split on newlines and process complete lines
        while let newlineRange = pendingData.range(of: Data([0x0A])) {
            let lineData = pendingData.subdata(in: pendingData.startIndex..<newlineRange.lowerBound)
            pendingData.removeSubrange(pendingData.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: lineData, options: []) as? [String: Any] else {
                continue
            }

            handleResponse(json)
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        // If there's a pending continuation, resume it with this response
        if let handler = responseHandler {
            responseHandler = nil
            handler.resume(returning: json)
        }
    }

    // MARK: - Stderr Reading

    private func startReadingStderr(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        Task.detached {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    // Log stderr output for debugging
                    print("[PythonBridge stderr] \(text)", terminator: "")
                }
            }
        }
    }

    // MARK: - Ready Signal

    private func waitForReady() async throws {
        // The first message from bridge.py should be {"type": "ready"}
        // We use the same continuation pattern but with a timeout
        let readyResponse: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            self.responseHandler = continuation
        }

        guard let type = readyResponse["type"] as? String, type == "ready" else {
            throw BridgeError.startupTimeout
        }
    }

    // MARK: - Process Termination

    private func handleProcessTermination() {
        isRunning = false

        // Fail any pending continuation
        if let handler = responseHandler {
            responseHandler = nil
            handler.resume(throwing: BridgeError.processNotRunning)
        }
    }
}
