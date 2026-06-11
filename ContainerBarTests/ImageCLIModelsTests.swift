import Testing
import Foundation
@testable import ContainerBar

// MARK: - Fixture loader (mirrors ContainerCLIModelsTests.swift)

private func loadImageFixture(named name: String, extension ext: String = "json") throws -> String {
    let bundle = Bundle(for: ImageFixtureBundleLocator.self)
    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") {
        return try String(contentsOf: url, encoding: .utf8)
    }
    if let url = bundle.url(forResource: name, withExtension: ext) {
        return try String(contentsOf: url, encoding: .utf8)
    }
    throw ImageFixtureError.notFound(name: "\(name).\(ext)")
}

private enum ImageFixtureError: Error {
    case notFound(name: String)
}

private final class ImageFixtureBundleLocator {}

// MARK: - Tests

@Suite("FlexibleContainerDecoder — images")
struct ImageCLIModelsTests {

    // MARK: image-list.json

    @Test("Decodes image-list.json: correct element count")
    func decodeImageListCount() throws {
        let json = try loadImageFixture(named: "image-list")
        let images = try FlexibleContainerDecoder.decodeImages(from: json)

        // Fixture contains 2 images: alpine:latest and postgres:latest
        #expect(images.count == 2)
    }

    @Test("Decodes image-list.json: alpine element — displayName, tag, reference, sizeBytes, architectures, createdAt")
    func decodeImageListAlpine() throws {
        let json = try loadImageFixture(named: "image-list")
        let images = try FlexibleContainerDecoder.decodeImages(from: json)

        let alpine = try #require(
            images.first(where: { $0.reference == "docker.io/library/alpine:latest" }),
            "alpine:latest should be present in image-list.json"
        )

        // docker.io/library/ prefix must be stripped
        #expect(alpine.displayName == "alpine")
        #expect(alpine.tag == "latest")
        #expect(alpine.reference == "docker.io/library/alpine:latest")

        // sizeBytes must be the sum of variants[].size, NOT configuration.descriptor.size.
        // Fixture: 1 variant with size = 4203982; descriptor.size = 9218 (manifest, wrong).
        let sizeBytes = try #require(alpine.sizeBytes)
        #expect(sizeBytes == 4_203_982)

        // architectures from variants[].platform.architecture
        #expect(alpine.architectures.contains("arm64"))

        // createdAt must parse
        #expect(alpine.createdAt != nil)

        // digestShort is first 12 chars of id
        #expect(alpine.digestShort == String(alpine.id.prefix(12)))
        #expect(alpine.digestShort.count == 12)

        // isInUse defaults to false (set by view model, not decoded)
        #expect(alpine.isInUse == false)
    }

    // MARK: image-inspect.json

    @Test("Decodes image-inspect.json: array shape with same element structure as list")
    func decodeImageInspect() throws {
        let json = try loadImageFixture(named: "image-inspect")
        let images = try FlexibleContainerDecoder.decodeImages(from: json)

        // inspect returns an array; alpine:latest has 1 element
        #expect(images.count == 1)

        let img = try #require(images.first)
        #expect(img.displayName == "alpine")
        #expect(img.tag == "latest")
    }

    // MARK: Inline-JSON edge cases

    @Test("Reference without tag: tag is nil, displayName is the full name part")
    func referenceWithoutTag() throws {
        let json = """
        [{"id":"abc123def456","configuration":{"name":"docker.io/library/ubuntu","creationDate":"2026-01-01T00:00:00Z"}}]
        """
        let images = try FlexibleContainerDecoder.decodeImages(from: json)
        let img = try #require(images.first)

        #expect(img.tag == nil)
        // docker.io/library/ stripped, no tag
        #expect(img.displayName == "ubuntu")
        #expect(img.reference == "docker.io/library/ubuntu")
    }

    @Test("Registry with port: registry:5000/app:v1 → displayName 'registry:5000/app', tag 'v1'")
    func registryWithPortAndTag() throws {
        let json = """
        [{"id":"abc123def456","configuration":{"name":"registry:5000/app:v1","creationDate":"2026-01-01T00:00:00Z"}}]
        """
        let images = try FlexibleContainerDecoder.decodeImages(from: json)
        let img = try #require(images.first)

        // The colon in 'registry:5000' must not be treated as the tag separator.
        #expect(img.displayName == "registry:5000/app")
        #expect(img.tag == "v1")
        #expect(img.reference == "registry:5000/app:v1")
    }

    @Test("Non-docker.io registry: prefix not stripped")
    func nonDockerIoRegistryNotStripped() throws {
        let json = """
        [{"id":"abc123def456","configuration":{"name":"ghcr.io/myorg/myapp:sha-abc","creationDate":"2026-01-01T00:00:00Z"}}]
        """
        let images = try FlexibleContainerDecoder.decodeImages(from: json)
        let img = try #require(images.first)

        // ghcr.io is not docker.io/library/ — must not be stripped
        #expect(img.displayName == "ghcr.io/myorg/myapp")
        #expect(img.tag == "sha-abc")
    }

    @Test("Missing variants: sizeBytes is nil")
    func missingVariantsSizeBytesNil() throws {
        let json = """
        [{"id":"abc123def456","configuration":{"name":"someimage:tag"}}]
        """
        let images = try FlexibleContainerDecoder.decodeImages(from: json)
        let img = try #require(images.first)

        // variants absent → sizeBytes nil
        #expect(img.sizeBytes == nil)
        #expect(img.architectures.isEmpty)
    }

    @Test("Unknown extra keys are tolerated (leniency policy)")
    func unknownKeysAreTolerated() throws {
        let json = """
        [{"id":"abc123def456","configuration":{"name":"myimage:latest"},"variants":[],"futureUnknownKey":{"nested":true}}]
        """
        // Must not throw despite the unknown key
        let images = try FlexibleContainerDecoder.decodeImages(from: json)
        #expect(images.count == 1)
    }

    // MARK: Garbage input

    @Test("Garbage input throws decodingFailed")
    func garbageInputThrowsDecodingFailed() throws {
        let badJSON = "this is not json"
        var caught: ContainerRuntimeError?
        do {
            _ = try FlexibleContainerDecoder.decodeImages(from: badJSON)
        } catch let error as ContainerRuntimeError {
            caught = error
        }
        let error = try #require(caught)
        if case .decodingFailed = error {
            // expected
        } else {
            Issue.record("Expected decodingFailed but got \(error)")
        }
    }

    @Test("Wrong-type JSON (object instead of array) throws decodingFailed")
    func wrongTypeThrowsDecodingFailed() throws {
        let json = """
        {"id":"abc","configuration":{"name":"foo:bar"}}
        """
        var caught: ContainerRuntimeError?
        do {
            _ = try FlexibleContainerDecoder.decodeImages(from: json)
        } catch let error as ContainerRuntimeError {
            caught = error
        }
        let error = try #require(caught)
        if case .decodingFailed = error {
            // expected
        } else {
            Issue.record("Expected decodingFailed but got \(error)")
        }
    }

    // MARK: imageReference on ContainerSummary

    @Test("toContainerSummary() populates imageReference with raw unstripped ref")
    func toContainerSummaryPopulatesImageReference() throws {
        // Inline a minimal list-element JSON that includes configuration.image.reference
        let json = """
        [
          {
            "id": "mycontainer",
            "configuration": {
              "image": { "reference": "docker.io/library/alpine:latest" },
              "creationDate": "2026-06-10T12:00:00Z"
            },
            "status": { "state": "running" }
          }
        ]
        """
        let containers = try FlexibleContainerDecoder.decodeList(from: json)
        let c = try #require(containers.first)

        // imageReference must be the raw ref — NOT stripped
        #expect(c.imageReference == "docker.io/library/alpine:latest")

        // image (display field) IS stripped
        #expect(c.image == "alpine:latest")
    }

    @Test("toContainerSummary() sets imageReference to nil when image ref is absent")
    func toContainerSummaryNilImageReference() throws {
        let json = """
        [
          {
            "id": "noimage",
            "status": { "state": "stopped" }
          }
        ]
        """
        let containers = try FlexibleContainerDecoder.decodeList(from: json)
        let c = try #require(containers.first)

        #expect(c.imageReference == nil)
    }
}
