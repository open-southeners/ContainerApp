import ContainerizationOCI
import ContainerResource
import Foundation
import Testing
@testable import ContainerApp

// MARK: - Helpers

/// An `ImageResource` with no variants for exercising reference parsing.
private func image(reference: String, created: Date = Date(timeIntervalSince1970: 1_767_225_600)) -> ImageResource {
    let descriptor = Descriptor(
        mediaType: "application/vnd.oci.image.index.v1+json",
        digest: "sha256:abc123def4567890",
        size: 9218
    )
    return ImageResource(
        configuration: .init(
            description: ImageDescription(reference: reference, descriptor: descriptor),
            creationDate: created
        ),
        variants: []
    )
}

// MARK: - Tests

@Suite("Image API model mapping")
struct ImageAPIModelsTests {

    // MARK: image-list.json

    @Test("Maps image-list.json: correct element count")
    func mapImageListCount() throws {
        let images = try decodeFixture([ImageResource].self, named: "image-list")
            .map { $0.toImageSummary() }

        // Fixture contains 2 images: alpine:latest and postgres:latest
        #expect(images.count == 2)
    }

    @Test("Maps image-list.json: alpine element — displayName, tag, reference, sizeBytes, architectures, createdAt")
    func mapImageListAlpine() throws {
        let images = try decodeFixture([ImageResource].self, named: "image-list")
            .map { $0.toImageSummary() }

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
        #expect(alpine.sizeBytes == 4_203_982)

        #expect(alpine.architectures.contains("arm64"))
        #expect(alpine.createdAt != nil)

        // digestShort is first 12 chars of id (digest without the sha256: prefix)
        #expect(alpine.digestShort == String(alpine.id.prefix(12)))
        #expect(alpine.digestShort.count == 12)
        #expect(!alpine.id.hasPrefix("sha256:"))

        // isInUse defaults to false (set by view model, not decoded)
        #expect(alpine.isInUse == false)
    }

    // MARK: image-inspect.json

    @Test("Maps image-inspect.json: array shape with same element structure as list")
    func mapImageInspect() throws {
        let images = try decodeFixture([ImageResource].self, named: "image-inspect")
            .map { $0.toImageSummary() }

        #expect(images.count == 1)

        let img = try #require(images.first)
        #expect(img.displayName == "alpine")
        #expect(img.tag == "latest")
    }

    // MARK: Reference edge cases

    @Test("Reference without tag: tag is nil, displayName is the full name part")
    func referenceWithoutTag() {
        let img = image(reference: "docker.io/library/ubuntu").toImageSummary()

        #expect(img.tag == nil)
        #expect(img.displayName == "ubuntu")
        #expect(img.reference == "docker.io/library/ubuntu")
    }

    @Test("Registry with port: registry:5000/app:v1 → displayName 'registry:5000/app', tag 'v1'")
    func registryWithPortAndTag() {
        let img = image(reference: "registry:5000/app:v1").toImageSummary()

        // The colon in 'registry:5000' must not be treated as the tag separator.
        #expect(img.displayName == "registry:5000/app")
        #expect(img.tag == "v1")
    }

    @Test("Non-docker.io registry: prefix not stripped")
    func nonDockerIoRegistryNotStripped() {
        let img = image(reference: "ghcr.io/myorg/myapp:sha-abc").toImageSummary()

        #expect(img.displayName == "ghcr.io/myorg/myapp")
        #expect(img.tag == "sha-abc")
    }

    @Test("No variants: size 0, no architectures")
    func noVariants() {
        let img = image(reference: "someimage:tag").toImageSummary()

        #expect(img.sizeBytes == 0)
        #expect(img.architectures.isEmpty)
    }

    @Test("Epoch creation date (no variant carried one) maps to nil createdAt")
    func epochCreationDate() {
        let img = image(reference: "someimage:tag", created: Date(timeIntervalSince1970: 0)).toImageSummary()
        #expect(img.createdAt == nil)
    }

    // MARK: Infrastructure images

    @Test("The runtime's init image is recognized regardless of tag")
    func infrastructureImageAnyTag() {
        // The library's default config names a newer vminit than an older install uses.
        let infra = [
            "ghcr.io/apple/containerization/vminit:0.47.0",
            "ghcr.io/apple/container-builder-shim/builder:0.13.1",
        ]
        #expect(isInfrastructureImage("ghcr.io/apple/containerization/vminit:0.33.3", infrastructureReferences: infra))
        #expect(isInfrastructureImage("ghcr.io/apple/container-builder-shim/builder:0.12.0", infrastructureReferences: infra))
        #expect(!isInfrastructureImage("docker.io/library/alpine:latest", infrastructureReferences: infra))
    }

    // MARK: imageReference on ContainerSummary

    @Test("toContainerSummary() keeps imageReference unstripped for in-use matching")
    func containerSummaryImageReference() throws {
        let c = try #require(
            try decodeFixture([ManagedContainer].self, named: "list-all").first
        ).toContainerSummary()

        // imageReference must be the raw ref — NOT stripped; image (display field) IS stripped
        #expect(c.imageReference == "docker.io/library/alpine:latest")
        #expect(c.image == "alpine:latest")
    }
}
