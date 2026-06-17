import Testing
import Foundation
@testable import ContainerApp

// MARK: - DockerCompatInstaller unit tests
//
// The pure layer (isInstalled/inserting/removing) is tested directly on String
// contents. The side-effecting layer is exercised against a temp file so no
// real shell rc is ever touched.

@Suite("DockerCompatInstaller pure layer")
struct DockerCompatInstallerPureTests {

    @Test("Empty file gets exactly the block")
    func insertIntoEmpty() {
        let result = DockerCompatInstaller.inserting(into: "")
        #expect(result == DockerCompatInstaller.block)
        #expect(DockerCompatInstaller.isInstalled(in: result))
    }

    @Test("Insert preserves existing content and appends block")
    func insertPreservesExisting() {
        let original = "export PATH=/usr/bin\nalias ll='ls -la'\n"
        let result = DockerCompatInstaller.inserting(into: original)
        #expect(result.hasPrefix(original))
        #expect(DockerCompatInstaller.isInstalled(in: result))
    }

    @Test("Insert is idempotent — block appears exactly once")
    func insertIsIdempotent() {
        let once = DockerCompatInstaller.inserting(into: "# rc\n")
        let twice = DockerCompatInstaller.inserting(into: once)
        #expect(once == twice)
        let occurrences = twice.components(separatedBy: DockerCompatInstaller.beginMarker).count - 1
        #expect(occurrences == 1)
    }

    @Test("Remove restores original content exactly (round-trip)")
    func removeRoundTrip() {
        let original = "export PATH=/usr/bin\nalias ll='ls -la'\n"
        let installed = DockerCompatInstaller.inserting(into: original)
        let removed = DockerCompatInstaller.removing(from: installed)
        #expect(removed == original)
        #expect(!DockerCompatInstaller.isInstalled(in: removed))
    }

    @Test("Remove is a no-op when block absent")
    func removeNoOp() {
        let original = "# nothing here\n"
        #expect(DockerCompatInstaller.removing(from: original) == original)
    }

    @Test("Repeated install/uninstall cycles do not accumulate blank lines")
    func cyclesAreStable() {
        let original = "line1\n"
        var contents = original
        for _ in 0..<3 {
            contents = DockerCompatInstaller.inserting(into: contents)
            contents = DockerCompatInstaller.removing(from: contents)
        }
        #expect(contents == original)
    }

    @Test("isInstalled reflects marker presence")
    func isInstalledDetection() {
        #expect(!DockerCompatInstaller.isInstalled(in: "no markers"))
        #expect(DockerCompatInstaller.isInstalled(in: DockerCompatInstaller.block))
    }
}

@Suite("DockerCompatInstaller shell resolution")
struct DockerCompatInstallerShellTests {

    @Test("zsh SHELL resolves to .zshrc")
    func zshResolution() {
        let shell = DockerCompatInstaller.loginShell(environment: ["SHELL": "/bin/zsh"])
        #expect(shell == .zsh)
        #expect(shell.rcFileName == ".zshrc")
    }

    @Test("bash SHELL resolves to .bash_profile")
    func bashResolution() {
        let shell = DockerCompatInstaller.loginShell(environment: ["SHELL": "/bin/bash"])
        #expect(shell == .bash)
        #expect(shell.rcFileName == ".bash_profile")
    }

    @Test("Missing SHELL defaults to zsh")
    func defaultsToZsh() {
        #expect(DockerCompatInstaller.loginShell(environment: [:]) == .zsh)
    }
}

@Suite("DockerCompatInstaller side effects")
struct DockerCompatInstallerSideEffectTests {

    /// A unique temp file path that does not yet exist.
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockercompat-\(UUID().uuidString).rc")
    }

    @Test("Install creates the file when absent and status reads true")
    func installCreatesFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!DockerCompatInstaller.status(at: url))
        try DockerCompatInstaller.install(at: url)
        #expect(DockerCompatInstaller.status(at: url))

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("docker-compose()"))
    }

    @Test("Install then uninstall leaves prior content intact")
    func installUninstallRoundTrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let original = "export EDITOR=vim\n"
        try original.write(to: url, atomically: true, encoding: .utf8)

        try DockerCompatInstaller.install(at: url)
        #expect(DockerCompatInstaller.status(at: url))

        try DockerCompatInstaller.uninstall(at: url)
        #expect(!DockerCompatInstaller.status(at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test("status reads false for a missing file")
    func statusMissingFile() {
        #expect(!DockerCompatInstaller.status(at: makeTempURL()))
    }
}
