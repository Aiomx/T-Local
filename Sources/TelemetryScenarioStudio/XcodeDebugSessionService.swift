import Foundation
import TelemetryLocationKit

struct XcodeDebugSessionService {
    func defaultWorkspacePath() -> String {
        for directory in defaultProjectDirectories() {
            let workspaceURL = directory.appendingPathComponent("EnterpriseTelemetryLocationQA.xcworkspace")
            if FileManager.default.fileExists(atPath: workspaceURL.path) {
                return workspaceURL.path
            }
        }
        return ""
    }

    func defaultRunnableScheme(workspaceOrProjectPath: String) -> String? {
        let schemeURLs = directSchemeURLs(workspaceOrProjectPath: workspaceOrProjectPath)
        let appSchemes = schemeURLs.compactMap { url -> String? in
            guard
                let xml = try? String(contentsOf: url, encoding: .utf8),
                xml.contains(#"BuildableName = ""#),
                xml.contains(".app")
            else {
                return nil
            }
            return url.deletingPathExtension().lastPathComponent
        }

        return appSchemes.first { $0.localizedCaseInsensitiveContains("Console") }
            ?? appSchemes.first { !$0.localizedCaseInsensitiveContains("Studio") }
            ?? appSchemes.first
    }

    func writeDebugGPX(for scenario: TelemetryScenario) throws -> URL {
        let directory = try debugLocationDirectory()
        let fileName = safeFileName(scenario.name).isEmpty ? "scenario" : safeFileName(scenario.name)
        let url = directory.appendingPathComponent("\(fileName).gpx")
        let gpx = try GPXExporter.export(scenario)
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func configureSchemeLocation(workspaceOrProjectPath: String, schemeName: String, gpxURL: URL) throws -> URL {
        let trimmedScheme = schemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScheme.isEmpty else {
            throw XcodeDebugSessionError.missingScheme
        }

        let schemeURL = try findSchemeURL(workspaceOrProjectPath: workspaceOrProjectPath, schemeName: trimmedScheme)
        var xml = try String(contentsOf: schemeURL, encoding: .utf8)
        guard let launchRange = xml.range(of: #"<LaunchAction\b[^>]*>"#, options: .regularExpression) else {
            throw XcodeDebugSessionError.schemeUpdateFailed("Scheme does not contain a LaunchAction.")
        }
        guard xml.range(of: "</LaunchAction>", range: launchRange.upperBound..<xml.endIndex) != nil else {
            throw XcodeDebugSessionError.schemeUpdateFailed("Scheme LaunchAction is not closed.")
        }

        let updatedLaunchTag = ensureLocationSimulationAllowed(String(xml[launchRange]))
        xml.replaceSubrange(launchRange, with: updatedLaunchTag)

        guard let updatedLaunchRange = xml.range(of: #"<LaunchAction\b[^>]*>"#, options: .regularExpression) else {
            throw XcodeDebugSessionError.schemeUpdateFailed("Scheme LaunchAction could not be re-read.")
        }
        guard let updatedLaunchCloseRange = xml.range(of: "</LaunchAction>", range: updatedLaunchRange.upperBound..<xml.endIndex) else {
            throw XcodeDebugSessionError.schemeUpdateFailed("Scheme LaunchAction could not be re-read.")
        }

        let bodyRange = updatedLaunchRange.upperBound..<updatedLaunchCloseRange.lowerBound
        let cleanedBody = removeExistingLocationReferences(String(xml[bodyRange]))
        let reference = locationScenarioReference(path: gpxURL.path)
        xml.replaceSubrange(bodyRange, with: "\n\(reference)\(cleanedBody)")

        try xml.write(to: schemeURL, atomically: true, encoding: .utf8)
        return schemeURL
    }

    func launchDebugSession(workspaceName: String, scheme: String, destination: String) async throws {
        let trimmedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScheme.isEmpty else {
            throw XcodeDebugSessionError.missingScheme
        }

        var arguments = ["xcdebug"]
        let trimmedWorkspace = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWorkspace.isEmpty {
            arguments.append(contentsOf: ["-w", trimmedWorkspace])
        }
        arguments.append(contentsOf: ["-s", trimmedScheme])
        arguments.append("-b")

        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty {
            arguments.append(contentsOf: ["-d", trimmedDestination])
        }

        arguments.append("-B")
        try await run("/usr/bin/xcrun", arguments: arguments)
    }

    private func findSchemeURL(workspaceOrProjectPath: String, schemeName: String) throws -> URL {
        for url in directSchemeURLs(workspaceOrProjectPath: workspaceOrProjectPath) {
            if url.lastPathComponent == "\(schemeName).xcscheme" {
                return url
            }
        }

        throw XcodeDebugSessionError.schemeNotFound(schemeName)
    }

    private func directSchemeURLs(workspaceOrProjectPath: String) -> [URL] {
        var candidates: [URL] = []
        for root in schemeSearchRoots(workspaceOrProjectPath: workspaceOrProjectPath) {
            if root.pathExtension == "xcodeproj" || root.pathExtension == "xcworkspace" {
                candidates.append(root)
            }
            if let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                candidates.append(contentsOf: children.filter { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" })
            }
        }

        return candidates.flatMap { container in
            let directory = container
                .appendingPathComponent("xcshareddata", isDirectory: true)
                .appendingPathComponent("xcschemes", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "xcscheme" } ?? []
        }
    }

    private func schemeSearchRoots(workspaceOrProjectPath: String) -> [URL] {
        let trimmedPath = workspaceOrProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputURL: URL
        if trimmedPath.isEmpty {
            inputURL = defaultProjectDirectories().first ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        } else {
            inputURL = URL(fileURLWithPath: trimmedPath)
        }

        if inputURL.pathExtension == "xcodeproj" || inputURL.pathExtension == "xcworkspace" {
            return [inputURL, inputURL.deletingLastPathComponent()]
        }
        return [inputURL]
    }

    private func defaultProjectDirectories() -> [URL] {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [sourceRoot, currentDirectory]
    }

    private func ensureLocationSimulationAllowed(_ launchTag: String) -> String {
        if launchTag.contains("allowLocationSimulation") {
            return launchTag.replacingOccurrences(
                of: #"allowLocationSimulation\s*=\s*"[^"]*""#,
                with: #"allowLocationSimulation = "YES""#,
                options: .regularExpression
            )
        }

        guard let insertIndex = launchTag.lastIndex(of: ">") else {
            return launchTag
        }

        var updated = launchTag
        updated.insert(contentsOf: "\n      allowLocationSimulation = \"YES\"", at: insertIndex)
        return updated
    }

    private func removeExistingLocationReferences(_ launchBody: String) -> String {
        launchBody.replacingOccurrences(
            of: #"\s*<LocationScenarioReference\b[^>]*(?:/?>|>[\s\S]*?</LocationScenarioReference>)"#,
            with: "",
            options: .regularExpression
        )
    }

    private func locationScenarioReference(path: String) -> String {
        """
            <LocationScenarioReference
               identifier = "\(xmlEscaped(path))"
               referenceType = "0">
            </LocationScenarioReference>
        """
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func debugLocationDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("TelemetryScenarioStudio", isDirectory: true)
            .appendingPathComponent("DebugLocations", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func safeFileName(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
    }

    @discardableResult
    private func run(_ executable: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let message = String(data: errorData, encoding: .utf8)
                        ?? String(data: output, encoding: .utf8)
                        ?? "Command failed."
                    continuation.resume(throwing: XcodeDebugSessionError.commandFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum XcodeDebugSessionError: LocalizedError {
    case missingScheme
    case schemeNotFound(String)
    case schemeUpdateFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScheme:
            "Enter the Xcode scheme that should be debugged."
        case let .schemeNotFound(schemeName):
            "Could not find \(schemeName).xcscheme under the workspace or project path."
        case let .schemeUpdateFailed(message):
            message
        case let .commandFailed(message):
            message
        }
    }
}
