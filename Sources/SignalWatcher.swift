import Foundation

final class SignalWatcher: @unchecked Sendable {
    private let baseDir: String
    private let onChange: ([Signal]) -> Void
    private var sourcesByPath: [String: DispatchSourceFileSystemObject] = [:]
    private let staleThreshold: TimeInterval = {
        if let env = ProcessInfo.processInfo.environment["DTACH_SIGNAL_STALE_HOURS"],
           let hours = Double(env) {
            return hours * 3600
        }
        return 4 * 3600 // 4 hours default
    }()
    private let queue = DispatchQueue(label: "cc-overlord.watcher")
    private var timer: DispatchSourceTimer?

    init(onChange: @escaping ([Signal]) -> Void) {
        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        self.baseDir = (tmpdir as NSString).appendingPathComponent("dtach-persist")
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.scan()
            self.watchDirectory(self.baseDir)
            self.watchAllSignalDirs()

            self.timer = DispatchSource.makeTimerSource(queue: self.queue)
            self.timer?.schedule(deadline: .now() + 5, repeating: 5)
            self.timer?.setEventHandler { [weak self] in
                guard let self else { return }
                // Retry base dir watch if it failed at launch (#9)
                if self.sourcesByPath[self.baseDir] == nil {
                    self.watchDirectory(self.baseDir)
                }
                self.watchAllSignalDirs()
                self.scan()
            }
            self.timer?.resume()
        }
    }

    private func watchAllSignalDirs() {
        guard let projects = try? FileManager.default.contentsOfDirectory(atPath: baseDir) else { return }
        for project in projects {
            let sigDir = (baseDir as NSString)
                .appendingPathComponent(project)
                .appending("/signals")
            if sourcesByPath[sigDir] == nil {
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

        // Cancel any existing watcher for this path (#7)
        sourcesByPath[path]?.cancel()
        sourcesByPath[path] = source
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

            let project = deriveProjectName(from: projectDir)
            let workspacePath = resolveWorkspacePath(projectDir: projectDir)

            for file in files {
                var matchedType: SignalType?
                var indexStr: String?

                for (ext, type) in SignalType.extensions {
                    if file.hasSuffix(ext) {
                        matchedType = type
                        indexStr = String(file.dropLast(ext.count))
                        break
                    }
                }

                guard let signalType = matchedType,
                      let idxStr = indexStr,
                      let index = Int(idxStr) else { continue }

                let filePath = (signalDir as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modified = attrs[.modificationDate] as? Date else { continue }

                if now.timeIntervalSince(modified) > staleThreshold {
                    try? fm.removeItem(atPath: filePath)
                    continue
                }

                signals.append(Signal(
                    project: project,
                    projectPath: workspacePath,
                    index: index,
                    timestamp: modified,
                    signalPath: filePath,
                    type: signalType
                ))
            }
        }

        onChange(signals)
    }

    func clearSignal(_ signal: Signal) {
        // Route through serial queue for thread safety (#11)
        queue.async { [weak self] in
            try? FileManager.default.removeItem(atPath: signal.signalPath)
            self?.scan()
        }
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
        // Read workspace.json written by the VS Code extension (#1)
        let metaPath = (baseDir as NSString)
            .appendingPathComponent(projectDir)
            .appending("/workspace.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let wsPath = json["path"] {
            return wsPath
        }

        // Fallback: guess from common locations
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
        return NSHomeDirectory() + "/Code/" + projectName
    }

    func stop() {
        timer?.cancel()
        sourcesByPath.values.forEach { $0.cancel() }
        sourcesByPath.removeAll()
    }
}
