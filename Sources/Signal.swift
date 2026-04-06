import Foundation

enum SignalType: String {
    case complete  // .signal
    case permission // .permission
    case error     // .error

    var label: String {
        switch self {
        case .complete: return "done"
        case .permission: return "needs approval"
        case .error: return "error"
        }
    }

    var icon: String {
        switch self {
        case .complete: return "●"
        case .permission: return "🔴"
        case .error: return "❌"
        }
    }

    var isUrgent: Bool {
        self == .permission || self == .error
    }

    static let extensions: [(ext: String, type: SignalType)] = [
        (".signal", .complete),
        (".permission", .permission),
        (".error", .error),
    ]
}

final class Signal: NSObject, @unchecked Sendable {
    let project: String
    let projectPath: String
    let index: Int
    let timestamp: Date
    let signalPath: String
    let type: SignalType

    init(project: String, projectPath: String, index: Int, timestamp: Date, signalPath: String, type: SignalType) {
        self.project = project
        self.projectPath = projectPath
        self.index = index
        self.timestamp = timestamp
        self.signalPath = signalPath
        self.type = type
    }

    var terminalName: String {
        let socketDir = URL(fileURLWithPath: signalPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let namesPath = (socketDir as NSString).appendingPathComponent("names.json")

        if let data = try? Data(contentsOf: URL(fileURLWithPath: namesPath)),
           let names = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let name = names[String(index)] {
            return name
        }
        return "Terminal \(index + 1)"
    }

    var agoString: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    func openInVSCode() {
        let signalsDir = (signalPath as NSString).deletingLastPathComponent
        let gotoPath = (signalsDir as NSString).appendingPathComponent("goto")
        try? String(index).write(toFile: gotoPath, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Visual Studio Code", projectPath]
        try? task.run()
    }
}
