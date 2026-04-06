import Foundation

final class Signal: NSObject, @unchecked Sendable {
    let project: String
    let projectPath: String
    let index: Int
    let timestamp: Date
    let signalPath: String

    init(project: String, projectPath: String, index: Int, timestamp: Date, signalPath: String) {
        self.project = project
        self.projectPath = projectPath
        self.index = index
        self.timestamp = timestamp
        self.signalPath = signalPath
    }

    var terminalName: String {
        // Try to read names.json from the socket directory
        let socketDir = (signalPath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/signals", with: "")
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
        // Write goto file so the extension knows which terminal to focus
        let signalsDir = (signalPath as NSString).deletingLastPathComponent
        let gotoPath = (signalsDir as NSString).appendingPathComponent("goto")
        try? String(index).write(toFile: gotoPath, atomically: true, encoding: .utf8)

        // Focus the VS Code window
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Visual Studio Code", projectPath]
        try? task.run()
    }
}
