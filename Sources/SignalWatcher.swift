import Foundation

final class SignalWatcher: @unchecked Sendable {
    private let baseDir: String
    private let onChange: ([Signal]) -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private let staleThreshold: TimeInterval = 15 * 60 // 15 minutes
    private let queue = DispatchQueue(label: "cc-overlord.watcher")
    private var timer: DispatchSourceTimer?
    private var watchedDirs = Set<String>()

    init(onChange: @escaping ([Signal]) -> Void) {
        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        self.baseDir = (tmpdir as NSString).appendingPathComponent("dtach-persist")
        self.onChange = onChange
    }

    func start() {
        // Scan immediately
        scan()

        // Watch the base directory for new project directories
        watchDirectory(baseDir)

        // Watch all existing signal directories
        watchAllSignalDirs()

        // Periodic scan to catch missed events, clean stale signals,
        // and watch any new signal directories
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + 5, repeating: 5)
        timer?.setEventHandler { [weak self] in
            self?.watchAllSignalDirs()
            self?.scan()
        }
        timer?.resume()
    }

    private func watchAllSignalDirs() {
        guard let projects = try? FileManager.default.contentsOfDirectory(atPath: baseDir) else { return }
        for project in projects {
            let sigDir = (baseDir as NSString)
                .appendingPathComponent(project)
                .appending("/signals")
            if !watchedDirs.contains(sigDir) {
                watchDirectory(sigDir)
            }
        }
    }

    private func watchDirectory(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scan()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        sources.append(source)
        watchedDirs.insert(path)
    }

    func scan() {
        var signals: [Signal] = []
        let fm = FileManager.default
        let now = Date()

        guard let projects = try? fm.contentsOfDirectory(atPath: baseDir) else {
            onChange([])
            return
        }

        for projectDir in projects {
            let projectPath = (baseDir as NSString).appendingPathComponent(projectDir)
            let signalDir = (projectPath as NSString).appendingPathComponent("signals")

            guard let files = try? fm.contentsOfDirectory(atPath: signalDir) else { continue }

            // Derive the project name — strip the hash suffix
            let project = deriveProjectName(from: projectDir)

            // Resolve the actual workspace path from the project dir name
            let workspacePath = resolveWorkspacePath(projectDir: projectDir)

            for file in files where file.hasSuffix(".signal") {
                let filePath = (signalDir as NSString).appendingPathComponent(file)
                let indexStr = (file as NSString).deletingPathExtension
                guard let index = Int(indexStr) else { continue }

                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modified = attrs[.modificationDate] as? Date else { continue }

                // Skip stale signals
                if now.timeIntervalSince(modified) > staleThreshold {
                    try? fm.removeItem(atPath: filePath)
                    continue
                }

                signals.append(Signal(
                    project: project,
                    projectPath: workspacePath,
                    index: index,
                    timestamp: modified,
                    signalPath: filePath
                ))
            }
        }

        onChange(signals)
    }

    func clearSignal(_ signal: Signal) {
        try? FileManager.default.removeItem(atPath: signal.signalPath)
        scan()
    }

    private func deriveProjectName(from dirName: String) -> String {
        // dirName is like "my-project-a1b2c3" — strip the last 7 chars (dash + 6 char hash)
        if dirName.count > 7 {
            let endIndex = dirName.index(dirName.endIndex, offsetBy: -7)
            return String(dirName[dirName.startIndex..<endIndex])
        }
        return dirName
    }

    private func resolveWorkspacePath(projectDir: String) -> String {
        // The socket dir name is "<folder-name>-<6-char-hash>"
        // We can't perfectly reverse this, but we can search common locations
        let projectName = deriveProjectName(from: projectDir)
        let candidates = [
            NSHomeDirectory() + "/Code/" + projectName,
            NSHomeDirectory() + "/Research/" + projectName,
            NSHomeDirectory() + "/Projects/" + projectName,
            NSHomeDirectory() + "/Desktop/" + projectName,
            NSHomeDirectory() + "/" + projectName,
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Fallback: best guess
        return NSHomeDirectory() + "/Code/" + projectName
    }
}
