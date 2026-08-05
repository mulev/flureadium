//
//  ReaderViewKindRoutingTests.swift
//  RunnerTests
//
//  Unit tests for readerViewKind(for:) — which reader view a publication is
//  routed to, and the precedence between the signals that decide it.
//

import XCTest
import ReadiumShared
@testable import flureadium

final class ReaderViewKindRoutingTests: XCTestCase {

    func testReturnsPdfForPdfPublication() {
        let publication = publication(
            profile: .pdf,
            readingOrder: [link(href: "/chapter.xhtml", type: .xhtml)]
        )

        XCTAssertEqual(readerViewKind(for: publication), .pdf)
    }

    func testReturnsImageForDivinaPublication() {
        let publication = publication(
            profile: .divina,
            readingOrder: [link(href: "/chapter.xhtml", type: .xhtml)]
        )

        XCTAssertEqual(readerViewKind(for: publication), .image)
    }

    func testReturnsImageForBitmapReadingOrder() {
        let publication = publication(
            profile: nil,
            readingOrder: [
                link(href: "/page-1.jpg", type: .jpeg),
                link(href: "/page-2.png", type: .png),
            ]
        )

        XCTAssertEqual(readerViewKind(for: publication), .image)
    }

    func testReturnsPdfWhenPublicationMatchesPdfAndImageSignals() {
        let publication = publication(
            profile: .pdf,
            readingOrder: [
                link(href: "/page-1.jpg", type: .jpeg),
                link(href: "/page-2.png", type: .png),
            ]
        )

        XCTAssertEqual(readerViewKind(for: publication), .pdf)
    }

    func testReturnsImageForSingleBitmapResource() {
        let publication = publication(
            profile: nil,
            readingOrder: [link(href: "/page-1.jpg", type: .jpeg)]
        )

        XCTAssertEqual(readerViewKind(for: publication), .image)
    }

    func testReturnsEpubForMixedBitmapAndHtmlReadingOrder() {
        let publication = publication(
            profile: nil,
            readingOrder: [
                link(href: "/page-1.jpg", type: .jpeg),
                link(href: "/chapter.xhtml", type: .xhtml),
            ]
        )

        XCTAssertEqual(readerViewKind(for: publication), .epub)
    }

    func testReturnsEpubForEmptyReadingOrder() {
        let publication = publication(profile: nil, readingOrder: [])

        XCTAssertEqual(readerViewKind(for: publication), .epub)
    }

    func testReturnsAudioForAudioReadingOrder() {
        let publication = publication(
            profile: nil,
            readingOrder: [
                link(href: "/track-1.mp3", type: .mp3),
                link(href: "/track-2.mp3", type: .mp3),
            ]
        )

        XCTAssertEqual(
            readerViewKind(for: publication), .audio,
            "Readium derives the audiobook profile from an all-audio reading order")
    }

    func testReturnsEpubForDeclaredAudiobookProfileOverHtmlReadingOrder() {
        let publication = publication(
            profile: .audiobook,
            readingOrder: [link(href: "/chapter.xhtml", type: .xhtml)]
        )

        XCTAssertEqual(
            readerViewKind(for: publication), .epub,
            "a media-overlay EPUB declares the audiobook profile but has pages to render")
    }

    func testReturnsEpubForMixedAudioAndHtmlReadingOrder() {
        let publication = publication(
            profile: nil,
            readingOrder: [
                link(href: "/track-1.mp3", type: .mp3),
                link(href: "/chapter.xhtml", type: .xhtml),
            ]
        )

        XCTAssertEqual(readerViewKind(for: publication), .epub)
    }

    func testReturnsPdfWhenPublicationMatchesPdfAndAudioSignals() {
        let publication = publication(
            profile: .pdf,
            readingOrder: [link(href: "/track-1.mp3", type: .mp3)]
        )

        XCTAssertEqual(
            readerViewKind(for: publication), .pdf, "the audio check must not move PDF precedence")
    }

    func testReturnsImageWhenPublicationMatchesDivinaAndAudioSignals() {
        let publication = publication(
            profile: .divina,
            readingOrder: [link(href: "/track-1.mp3", type: .mp3)]
        )

        XCTAssertEqual(
            readerViewKind(for: publication), .image,
            "the audio check must not move DiViNa precedence")
    }

    func testReturnsEpubForDeclaredAudiobookProfileOverEmptyReadingOrder() {
        let publication = publication(profile: .audiobook, readingOrder: [])

        XCTAssertEqual(
            readerViewKind(for: publication), .epub,
            "Readium guards conforms(to:) with a non-empty reading order")
    }

    private func publication(profile: Publication.Profile?, readingOrder: [Link]) -> Publication {
        var conformsTo: [Publication.Profile] = []
        if let profile {
            conformsTo = [profile]
        }

        return Publication(
            manifest: Manifest(
                metadata: Metadata(conformsTo: conformsTo, title: "Reader Kind"),
                readingOrder: readingOrder
            )
        )
    }

    private func link(href: String, type: MediaType) -> Link {
        Link(href: href, mediaType: type)
    }
}

