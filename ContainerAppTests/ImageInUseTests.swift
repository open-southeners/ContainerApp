import Testing
import Foundation
@testable import ContainerApp

// MARK: - Helpers

/// Builds a minimal `ImageSummary` with just the fields used by `markInUse`.
private func makeImage(id: String, reference: String) -> ImageSummary {
    ImageSummary(
        id: id,
        reference: reference,
        displayName: reference,
        tag: nil,
        digestShort: String(id.prefix(12)),
        createdAt: nil,
        sizeBytes: nil,
        architectures: []
    )
}

/// Builds a minimal `ContainerSummary` with just `imageReference` set.
private func makeContainer(id: String, imageReference: String?) -> ContainerSummary {
    ContainerSummary(
        id: id,
        name: id,
        image: imageReference ?? "",
        state: .running,
        status: nil,
        command: nil,
        createdAt: nil,
        startedAt: nil,
        ports: nil,
        cpuText: nil,
        memoryText: nil,
        imageReference: imageReference
    )
}

// MARK: - Tests

@Suite("ContainersViewModel markInUse")
struct ImageInUseTests {

    // MARK: Exact match

    @Test("Exact reference match marks image as in-use")
    func exactMatchMarksInUse() throws {
        let ref = "docker.io/library/alpine:latest"
        let images = [makeImage(id: "aabbcc112233", reference: ref)]
        let containers = [makeContainer(id: "c1", imageReference: ref)]

        let result = ContainersViewModel.markInUse(images, containers: containers)

        let img = try #require(result.first)
        #expect(img.isInUse == true)
    }

    // MARK: Non-matching reference

    @Test("Non-matching imageReference leaves image isInUse false")
    func nonMatchingReferenceStaysFalse() throws {
        let images = [makeImage(id: "aabbcc112233", reference: "docker.io/library/alpine:latest")]
        let containers = [makeContainer(id: "c1", imageReference: "docker.io/library/ubuntu:22.04")]

        let result = ContainersViewModel.markInUse(images, containers: containers)

        let img = try #require(result.first)
        #expect(img.isInUse == false)
    }

    // MARK: Multiple containers on one image

    @Test("Multiple containers sharing the same image ref still marks image once (true)")
    func multipleContainersSameImage() throws {
        let ref = "docker.io/library/postgres:latest"
        let images = [makeImage(id: "ddee99001122", reference: ref)]
        let containers = [
            makeContainer(id: "db1", imageReference: ref),
            makeContainer(id: "db2", imageReference: ref),
            makeContainer(id: "db3", imageReference: ref),
        ]

        let result = ContainersViewModel.markInUse(images, containers: containers)

        // Only one image in the result, and it must be marked in-use.
        #expect(result.count == 1)
        let img = try #require(result.first)
        #expect(img.isInUse == true)
    }

    // MARK: nil imageReference

    @Test("Container with nil imageReference never matches any image")
    func nilImageReferenceMatchesNothing() throws {
        let images = [makeImage(id: "aabbcc112233", reference: "docker.io/library/alpine:latest")]
        let containers = [makeContainer(id: "c1", imageReference: nil)]

        let result = ContainersViewModel.markInUse(images, containers: containers)

        let img = try #require(result.first)
        #expect(img.isInUse == false)
    }

    // MARK: Empty inputs

    @Test("Empty images list returns empty result")
    func emptyImagesReturnsEmpty() {
        let containers = [makeContainer(id: "c1", imageReference: "docker.io/library/alpine:latest")]

        let result = ContainersViewModel.markInUse([], containers: containers)

        #expect(result.isEmpty)
    }

    @Test("Empty containers list leaves all images isInUse false")
    func emptyContainersAllFalse() {
        let images = [
            makeImage(id: "aabbcc112233", reference: "docker.io/library/alpine:latest"),
            makeImage(id: "ddeeff445566", reference: "docker.io/library/ubuntu:22.04"),
        ]

        let result = ContainersViewModel.markInUse(images, containers: [])

        #expect(result.count == 2)
        #expect(result.allSatisfy { !$0.isInUse })
    }

    // MARK: Mixed in-use and not-in-use

    @Test("Only matching images are marked; non-matching stay false")
    func mixedInUseAndNot() throws {
        let refAlpine = "docker.io/library/alpine:latest"
        let refUbuntu = "docker.io/library/ubuntu:22.04"
        let images = [
            makeImage(id: "aabbcc112233", reference: refAlpine),
            makeImage(id: "ddeeff445566", reference: refUbuntu),
        ]
        // Only alpine is in use.
        let containers = [makeContainer(id: "c1", imageReference: refAlpine)]

        let result = ContainersViewModel.markInUse(images, containers: containers)

        let alpine = try #require(result.first { $0.reference == refAlpine })
        let ubuntu = try #require(result.first { $0.reference == refUbuntu })

        #expect(alpine.isInUse == true)
        #expect(ubuntu.isInUse == false)
    }
}
