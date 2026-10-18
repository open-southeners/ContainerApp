import Foundation
import Testing
@testable import ContainerApp

/// The licenses of the linked open-source packages must ship inside the app bundle.
@Suite("Third-party notices")
struct ThirdPartyNoticesTests {

    private func notices() throws -> String {
        let url = try #require(
            Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            "ThirdPartyNotices.txt should be bundled — run scripts/generate-third-party-notices.py"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Bundled notices cover Apple's container libraries and their NOTICE files")
    func coversContainerLibraries() throws {
        let text = try notices()
        #expect(text.contains("https://github.com/apple/container — version"))
        #expect(text.contains("https://github.com/apple/containerization — version"))
        #expect(text.contains("NOTICE.md:"))
    }

    @Test("Bundled notices include licenses of vendored C libraries")
    func coversVendoredLibraries() throws {
        let text = try notices()
        #expect(text.contains("BoringSSL (vendored as CNIOBoringSSL)"))
        #expect(text.contains("LibYAML (vendored as CYaml)"))
    }
}
