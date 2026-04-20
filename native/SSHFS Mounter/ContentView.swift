import SwiftUI
import Foundation

struct Connection: Identifiable, Codable {
    var id: String
    var title: String
    var server: String
    var port: String
    var user: String
    var password: String
    var key: String
    var remote: String
    var mount: String
    var savepass: Bool

    init(id: String = "", title: String = "", server: String = "", port: String = "22",
         user: String = "", password: String = "", key: String = "",
         remote: String = "", mount: String = "", savepass: Bool = false) {
        self.id = id
        self.title = title
        self.server = server
        self.port = port
        self.user = user
        self.password = password
        self.key = key
        self.remote = remote
        self.mount = mount
        self.savepass = savepass
    }
}

class SettingsManager: ObservableObject {
    @Published var connections: [String: Connection] = [:]

    private let settingsPath: String

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("sshfs-mounter")
        settingsPath = appDir.appendingPathComponent("settings.json").path

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        loadSettings()
    }

    func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return }
        guard let data = FileManager.default.contents(atPath: settingsPath) else { return }

        do {
            let decoder = JSONDecoder()
            let container = try decoder.decode([String: Connection].self, from: data)
            DispatchQueue.main.async {
                self.connections = container
            }
        } catch {
            print("Error loading settings: \(error)")
        }
    }

    func saveSettings() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(connections)
            try data.write(to: URL(fileURLWithPath: settingsPath))
        } catch {
            print("Error saving settings: \(error)")
        }
    }

    func saveConnection(_ conn: Connection) {
        connections[conn.id] = conn
        saveSettings()
    }

    func deleteConnection(id: String) {
        connections.removeValue(forKey: id)
        saveSettings()
    }
}

class SSHFSManager: ObservableObject {
    @Published var sshfsPath: String?
    @Published var umountPath: String?
    @Published var output: String = ""
    @Published var mountedConnections: Set<String> = []

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.findCommands()
        }
    }

    func findCommands() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-i", "-c", "which sshfs"]

            let pipe = Pipe()
            task.standardOutput = pipe

            var foundSshfs: String?
            var sshfsNotFound = false

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty && task.terminationStatus == 0 {
                    foundSshfs = path
                } else {
                    sshfsNotFound = true
                }
            } catch {
                sshfsNotFound = true
            }

            var foundUmount: String?
            let umountTask = Process()
            umountTask.launchPath = "/bin/zsh"
            umountTask.arguments = ["-i", "-c", "which umount"]

            let umountPipe = Pipe()
            umountTask.standardOutput = umountPipe

            do {
                try umountTask.run()
                let data = umountPipe.fileHandleForReading.readDataToEndOfFile()
                umountTask.waitUntilExit()

                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    foundUmount = path
                }
            } catch {
                // Use default
            }

            DispatchQueue.main.async {
                if let path = foundSshfs {
                    self.sshfsPath = path
                    self.appendOutput("sshfs found at: \(path)\n")
                } else if sshfsNotFound {
                    self.sshfsPath = nil
                    self.appendOutput("ERROR: sshfs not found. Please install it:\n")
                    self.appendOutput("  brew install --cask macfuse\n")
                    self.appendOutput("  brew install gromgit/fuse/sshfs-mac\n")
                }
                self.umountPath = foundUmount ?? "/usr/sbin/umount"
            }
        }
    }

    func appendOutput(_ message: String) {
        DispatchQueue.main.async {
            self.output += message
        }
    }

    func mount(_ conn: Connection) {
        guard let sshfsPath = sshfsPath else {
            appendOutput("ERROR: sshfs not found\n")
            return
        }

        var options: [String] = ["volname=\(conn.title)", "auto_cache", "reconnect"]
        var cmdParts: [String] = []

        if !conn.password.isEmpty {
            cmdParts.append("echo")
            cmdParts.append("'\(conn.password)'")
            cmdParts.append("|")
            options.append("password_stdin")
        }

        if !conn.key.isEmpty {
            options.append("IdentityFile=\(conn.key)")
        }

        cmdParts.append(sshfsPath)

        let remote: String
        if !conn.user.isEmpty {
            remote = "\(conn.user)@\(conn.server):\(conn.remote)"
        } else {
            remote = "\(conn.server):\(conn.remote)"
        }
        cmdParts.append(remote)
        cmdParts.append(conn.mount)
        cmdParts.append("-o")
        cmdParts.append(options.joined(separator: ","))

        if !conn.port.isEmpty {
            cmdParts.append("-p")
            cmdParts.append(conn.port)
        }

        let command = cmdParts.joined(separator: " ")
        let displayCommand = command.replacingOccurrences(
            of: "'\(conn.password)'",
            with: "[password]",
            options: .literal
        )

        appendOutput("\(displayCommand)\n")

        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-i", "-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let outputStr = String(data: data, encoding: .utf8) {
                if task.terminationStatus == 0 {
                    appendOutput("Mounted successfully\n")
                    DispatchQueue.main.async {
                        self.mountedConnections.insert(conn.id)
                    }
                } else if outputStr.contains("segmentation fault") || task.terminationStatus == 139 {
                    appendOutput("ERROR: sshfs crashed. This is a known macOS Sequoia compatibility issue.\n\n")
                    appendOutput("To fix this, install FUSE-T (replaces macFUSE):\n")
                    appendOutput("  1. Uninstall macFUSE: brew uninstall --cask macfuse\n")
                    appendOutput("  2. Install FUSE-T: brew install --cask fuse-t\n")
                    appendOutput("  3. Reinstall sshfs: brew reinstall gromgit/fuse/sshfs-mac\n")
                    appendOutput("  4. Restart your computer\n")
                } else {
                    appendOutput("Mount failed: \(outputStr)\n")
                }
            }
        } catch {
            appendOutput("Mount error: \(error.localizedDescription)\n")
        }
    }

    func unmount(_ conn: Connection) {
        let umountPath = umountPath ?? "/usr/sbin/umount"
        let command = "\(umountPath) \(conn.mount)"

        appendOutput("\(command)\n")

        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-i", "-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let outputStr = String(data: data, encoding: .utf8) {
                if task.terminationStatus == 0 {
                    appendOutput("Unmounted\n")
                    DispatchQueue.main.async {
                        self.mountedConnections.remove(conn.id)
                    }
                } else {
                    appendOutput("\(outputStr)\n")
                }
            }
        } catch {
            appendOutput("Unmount error: \(error.localizedDescription)\n")
        }
    }

    func refreshMountStatus(_ connections: [String: Connection]) {
        DispatchQueue.global().async {
            var mounted: Set<String> = []
            for (id, conn) in connections {
                let task = Process()
                task.launchPath = "/bin/zsh"
                task.arguments = ["-i", "-c", "mount | grep -q '\(conn.mount)'"]

                do {
                    try task.run()
                    task.waitUntilExit()
                    if task.terminationStatus == 0 {
                        mounted.insert(id)
                    }
                } catch {
                    // Ignore errors
                }
            }
            DispatchQueue.main.async {
                self.mountedConnections = mounted
            }
        }
    }
}

struct ConnectionListItem: View {
    let id: String
    let title: String
    let isMounted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isMounted ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView: View {
    @StateObject private var settings = SettingsManager()
    @StateObject private var sshfs = SSHFSManager()

    @State private var selectedConnectionId: String?
    @State private var formTitle: String = ""
    @State private var formServer: String = ""
    @State private var formPort: String = "22"
    @State private var formUser: String = ""
    @State private var formPassword: String = ""
    @State private var formKey: String = ""
    @State private var formRemote: String = ""
    @State private var formMount: String = ""
    @State private var formSavePass: Bool = false

    let labelWidth: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left sidebar
                VStack(spacing: 0) {
                    List(selection: $selectedConnectionId) {
                        ForEach(settings.connections.keys.sorted(), id: \.self) { key in
                            if let conn = settings.connections[key] {
                                ConnectionListItem(
                                    id: key,
                                    title: conn.title,
                                    isMounted: sshfs.mountedConnections.contains(key)
                                )
                                .tag(key)
                            }
                        }
                    }
                    .listStyle(.inset)

                    Divider()

                    HStack(spacing: 8) {
                        Button(action: addNewConnection) {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)

                        Button(action: deleteSelectedConnection) {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedConnectionId == nil)

                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: 200)

                Divider()

                // Right panel
                VStack(alignment: .trailing, spacing: 12) {
                    // Connection section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Volume title:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formTitle)
                            }

                            HStack {
                                Text("Server:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formServer)

                                Text("Port:")
                                    .frame(width: 40, alignment: .trailing)
                                TextField("", text: $formPort)
                                    .frame(width: 60)
                            }

                            HStack {
                                Text("Username:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formUser)
                            }

                            HStack {
                                Text("Password:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                SecureField("", text: $formPassword)
                            }

                            HStack {
                                Spacer()
                                Toggle("Save password", isOn: $formSavePass)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }

                    // SSH section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SSH")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Key file:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formKey)
                            }

                            HStack {
                                Text("Remote dir:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formRemote)
                            }

                            HStack {
                                Text("Mount dir:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                TextField("", text: $formMount)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Spacer()

                        Button("Save") {
                            saveConnection()
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(selectedConnectionId == nil)

                        Button("Mount") {
                            if let conn = getCurrentConnection() {
                                sshfs.mount(conn)
                            }
                        }
                        .disabled(selectedConnectionId == nil)

                        Button("Unmount") {
                            if let conn = getCurrentConnection() {
                                sshfs.unmount(conn)
                            }
                        }
                        .disabled(selectedConnectionId == nil)
                    }
                    .padding(.top, 8)

                    Spacer()
                }
                .padding()
            }

            Divider()

            // Log section
            VStack(alignment: .leading, spacing: 4) {
                Text("Connection log:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                TextEditor(text: $sshfs.output)
                    .font(.system(.caption, design: .monospaced))
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                    .border(Color(NSColor.separatorColor), width: 1)
            }
            .padding(8)
            .frame(height: 120)
        }
        .padding(8)
        .onChange(of: selectedConnectionId) { newId in
            loadConnection(newId)
        }
        .onAppear {
            settings.loadSettings()
            sshfs.refreshMountStatus(settings.connections)
        }
    }

    private func addNewConnection() {
        let nextId = generateNextId()
        let newConn = Connection(id: nextId, title: nextId)
        settings.saveConnection(newConn)
        selectedConnectionId = nextId
    }

    private func deleteSelectedConnection() {
        guard let id = selectedConnectionId else { return }
        settings.deleteConnection(id: id)
        selectedConnectionId = nil
        clearForm()
    }

    private func saveConnection() {
        guard let id = selectedConnectionId else { return }

        var conn = Connection(
            id: formTitle,
            title: formTitle,
            server: formServer,
            port: formPort,
            user: formUser,
            password: formSavePass ? formPassword : "",
            key: formKey,
            remote: formRemote,
            mount: formMount,
            savepass: formSavePass
        )

        if id != formTitle {
            settings.deleteConnection(id: id)
        }

        settings.saveConnection(conn)
        selectedConnectionId = formTitle
    }

    private func loadConnection(_ id: String?) {
        guard let id = id, let conn = settings.connections[id] else {
            clearForm()
            return
        }

        formTitle = conn.title
        formServer = conn.server
        formPort = conn.port
        formUser = conn.user
        formPassword = conn.password
        formKey = conn.key
        formRemote = conn.remote
        formMount = conn.mount
        formSavePass = conn.savepass
    }

    private func clearForm() {
        formTitle = ""
        formServer = ""
        formPort = "22"
        formUser = ""
        formPassword = ""
        formKey = ""
        formRemote = ""
        formMount = ""
        formSavePass = false
    }

    private func generateNextId() -> String {
        var index = 1
        var nextId = "server-\(index)"

        while settings.connections.keys.contains(nextId) {
            index += 1
            nextId = "server-\(index)"
        }

        return nextId
    }

    private func getCurrentConnection() -> Connection? {
        guard let id = selectedConnectionId else { return nil }
        if let conn = settings.connections[id] {
            return conn
        }
        return Connection(
            id: formTitle,
            title: formTitle,
            server: formServer,
            port: formPort,
            user: formUser,
            password: formPassword,
            key: formKey,
            remote: formRemote,
            mount: formMount,
            savepass: formSavePass
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
