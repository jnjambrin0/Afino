import Foundation
@testable import PIApp
import PIDesign
import Testing

/// The paced reveal: release sizes, grapheme safety, word ends, line-start markup, the lag bound.
struct StreamRevealBufferTests {
    // MARK: Helpers

    /// Ticks until everything is revealed (or `limit` ticks pass), returning the releases.
    private func drain(_ buffer: inout StreamRevealBuffer, limit: Int = 10_000) -> [StreamRevealBuffer.Release] {
        var releases: [StreamRevealBuffer.Release] = []
        var ticks = 0
        while !buffer.isDrained, ticks < limit {
            if let release = buffer.tick() {
                releases.append(release)
            }
            ticks += 1
        }
        return releases
    }

    private func exactlyEqual(_ a: some StringProtocol, _ b: some StringProtocol) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// UTF-8 offsets of every grapheme-cluster boundary of `text`.
    private func clusterBoundaries(_ text: String) -> Set<Int> {
        var offsets: Set<Int> = [text.utf8.count]
        for index in text.indices {
            offsets.insert(text.utf8.distance(from: text.utf8.startIndex, to: index))
        }
        return offsets
    }

    // MARK: Release sizes

    @Test func releasesFollowTheDrainToken() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000, wordBoundaryLookahead: 0)
        #expect(buffer.receive(String(repeating: "x", count: 100)) == .appended)
        #expect(buffer.pendingCount == 100)

        var sizes: [Int] = []
        while let release = buffer.tick() {
            sizes.append(release.text.count)
        }
        #expect(sizes.prefix(4) == [20, 16, 13, 11])
        #expect(sizes.reduce(0, +) == 100)
        // The tail never drops below the minimum release, except for the very last character.
        #expect(sizes.dropLast().allSatisfy { $0 >= EmberDesign.Stream.minimumRelease })
        for (index, size) in sizes.enumerated() {
            let pendingBefore = 100 - sizes.prefix(index).reduce(0, +)
            #expect(size == EmberDesign.Stream.releaseCount(pending: pendingBefore))
        }
    }

    @Test func tinyPendingReleasesAtLeastTwoCharacters() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000, wordBoundaryLookahead: 0)
        _ = buffer.receive("abcde")
        #expect(buffer.tick()?.text == "ab")
        #expect(buffer.tick()?.text == "cd")
        #expect(buffer.tick()?.text == "e")
        #expect(buffer.tick() == nil)
        #expect(buffer.isDrained)
    }

    @Test func releasesCarryTheirStorageOffsets() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000, wordBoundaryLookahead: 0)
        _ = buffer.receive("😀😀😀😀😀")
        let first = buffer.tick()
        #expect(first?.text == "😀😀")
        #expect(first?.utf16Range == NSRange(location: 0, length: 4))
        let second = buffer.tick()
        #expect(second?.utf16Range == NSRange(location: 4, length: 4))
        #expect(buffer.revealedUTF16 == 8)
    }

    // MARK: Graphemes

    @Test func neverSplitsAGraphemeCluster() {
        let samples = [
            "👨‍👩‍👧‍👦 family 🇪🇸🇫🇷🇯🇵 flags 👍🏽👍🏿 tones",
            "e\u{301}e\u{301}e\u{301} cafe\u{301} na\u{303}o a\u{308}\u{304}\u{301}",
            "line one\r\nline two\r\n\r\nline four",
            "한국어 텍스트 ᄀᄀᄀ각 🏳️‍🌈 ok",
        ]
        for lookahead in [0, EmberDesign.Stream.wordBoundaryLookahead] {
            for sample in samples {
                var buffer = StreamRevealBuffer(wordBoundaryLookahead: lookahead)
                _ = buffer.receive(sample)
                let boundaries = clusterBoundaries(sample)
                var revealed = ""
                for release in drain(&buffer) {
                    revealed += release.text
                    #expect(boundaries.contains(revealed.utf8.count), "split inside a cluster: \(revealed.debugDescription)")
                }
                #expect(exactlyEqual(revealed, sample))
            }
        }
    }

    @Test func aCombiningMarkDeliveredLaterCompletesTheCluster() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("cafe")
        _ = drain(&buffer)
        #expect(buffer.receive("cafe\u{301} ok") == .appended)
        let release = buffer.tick()
        #expect(release?.text.unicodeScalars.first == "\u{301}")
        _ = drain(&buffer)
        #expect(exactlyEqual(buffer.revealedText, "cafe\u{301} ok"))
    }

    @Test func aCRLFSplitAcrossDeliveriesStaysExact() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("first\r")
        _ = drain(&buffer)
        #expect(buffer.receive("first\r\nsecond") == .appended)
        _ = drain(&buffer)
        #expect(exactlyEqual(buffer.revealedText, "first\r\nsecond"))
        #expect(buffer.revealedUTF16 == "first\r\nsecond".utf16.count)
    }

    @Test func canonicallyEquivalentTextIsNotAnExtension() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("cafe\u{301}")
        _ = drain(&buffer)
        // "café" precomposed is equal as a Swift String, but not the same characters.
        #expect(buffer.receive("caf\u{E9} au lait") == .replaced)
        #expect(buffer.isDrained)
        #expect(exactlyEqual(buffer.revealedText, "caf\u{E9} au lait"))
    }

    @Test func everyReleaseEndsOnABoundaryOfTheTextAtThatTime() {
        let text = """
        # Role
        You are a senior 🧑‍💻 engineer. Write <document> tags, `code` and e\u{301}motions.\r
        - first 🇪🇸
        - second 👍🏽

        ```swift
        let x = 1
        ```
        Done.
        """
        let scalars = Array(text.unicodeScalars)
        var random = SplitMix64(seed: 0x5EED)
        for _ in 0..<40 {
            var buffer = StreamRevealBuffer()
            var delivered = 0
            var revealed = ""
            while delivered < scalars.count || !buffer.isDrained {
                if delivered < scalars.count, random.next() % 3 != 0 {
                    delivered = min(scalars.count, delivered + Int(random.next() % 9) + 1)
                    var view = String.UnicodeScalarView()
                    view.append(contentsOf: scalars[..<delivered])
                    #expect(buffer.receive(String(view)) == .appended)
                }
                if delivered == scalars.count {
                    buffer.finish()
                }
                if let release = buffer.tick() {
                    revealed += release.text
                    #expect(clusterBoundaries(buffer.text).contains(revealed.utf8.count))
                }
            }
            #expect(exactlyEqual(revealed, text))
        }
    }

    // MARK: Word ends

    @Test func prefersEndingAfterWhitespaceWithinTheLookahead() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000)
        _ = buffer.receive("The quick brown fox jumps")
        // Five characters are due ("The q"); the release runs on to the end of "quick ".
        #expect(buffer.tick()?.text == "The quick ")
    }

    @Test func splitsALongWordWhenNoWhitespaceIsNear() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000)
        _ = buffer.receive("Supercalifragilisticexpialidocious and")
        // Eight characters are due and no whitespace lies within the next twelve.
        #expect(buffer.tick()?.text == "Supercal")
    }

    // MARK: Line-start markup

    @Test func holdsBackAnUndecidedHeadingMarker() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("Intro\n#")
        _ = drain(&buffer, limit: 20)
        // "#" alone could be a heading or a hashtag: it waits.
        #expect(exactlyEqual(buffer.revealedText, "Intro\n"))
        _ = buffer.receive("Intro\n# Title")
        let release = buffer.tick()
        #expect(release?.text.hasPrefix("# ") == true)
    }

    @Test func revealsAFenceOpeningAsOneRun() {
        var buffer = StreamRevealBuffer(maximumLagTicks: 10_000, wordBoundaryLookahead: 0)
        _ = buffer.receive("Text\n``")
        _ = drain(&buffer, limit: 20)
        #expect(exactlyEqual(buffer.revealedText, "Text\n"))
        _ = buffer.receive("Text\n```swift\nlet x = 1\n")
        var revealed = String(buffer.revealedText)
        while let release = buffer.tick() {
            revealed += release.text
            let lastLine = revealed.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
            #expect(lastLine != "`" && lastLine != "``", "a fence was split: \(revealed.debugDescription)")
        }
    }

    @Test func aFinishedStreamReleasesTrailingMarkup() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("Notes\n#")
        _ = drain(&buffer, limit: 20)
        #expect(!buffer.isDrained)
        buffer.finish()
        _ = drain(&buffer, limit: StreamLocalTokens.maximumLagTicks)
        #expect(exactlyEqual(buffer.revealedText, "Notes\n#"))
    }

    // MARK: Lag

    @Test func aLargeBurstDrainsWithinTheLagBound() {
        var buffer = StreamRevealBuffer()
        let burst = String(repeating: "word ", count: 1_000)
        _ = buffer.receive(burst)
        var sizes: [Int] = []
        var ticks = 0
        while !buffer.isDrained {
            ticks += 1
            if let release = buffer.tick() {
                sizes.append(release.text.count)
            }
        }
        #expect(ticks <= StreamLocalTokens.maximumLagTicks)
        #expect(Double(ticks) * EmberDesign.Stream.drainInterval <= StreamLocalTokens.maximumLag)
        // Even: the deadline turns the exponential tail into a steady rate, so no release is
        // more than about twice the average.
        let average = Double(burst.count) / Double(sizes.count)
        #expect(sizes.allSatisfy { Double($0) <= average * 2 })
    }

    @Test func aSteadyStreamNeverLagsMoreThanTheBound() {
        var buffer = StreamRevealBuffer()
        var text = ""
        var deliveries: [(end: Int, tick: Int)] = []
        var revealedAt: [Int: Int] = [:]
        var random = SplitMix64(seed: 42)
        for tick in 0..<300 {
            if tick < 250, random.next() % 2 == 0 {
                text += String(repeating: "lorem ipsum ", count: Int(random.next() % 4) + 1)
                _ = buffer.receive(text)
                deliveries.append((text.utf8.count, tick))
            }
            _ = buffer.tick()
            for (index, delivery) in deliveries.enumerated() where revealedAt[index] == nil {
                if buffer.revealedText.utf8.count >= delivery.end {
                    revealedAt[index] = tick
                }
            }
        }
        for (index, delivery) in deliveries.enumerated() {
            let lag = (revealedAt[index] ?? .max) - delivery.tick
            #expect(lag < StreamLocalTokens.maximumLagTicks, "delivery \(index) waited \(lag) ticks")
        }
    }

    @Test func finishDrainsEverythingWithinTheLagBound() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive(String(repeating: "abc def ", count: 300))
        _ = buffer.tick()
        _ = buffer.tick()
        buffer.finish()
        var ticks = 0
        while !buffer.isDrained, ticks < 100 {
            _ = buffer.tick()
            ticks += 1
        }
        #expect(buffer.isDrained)
        #expect(ticks <= StreamLocalTokens.maximumLagTicks)
    }

    @Test func flushRevealsEverythingAtOnce() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("one two three four five")
        let release = buffer.flush()
        #expect(release?.text == "one two three four five")
        #expect(buffer.isDrained)
        #expect(buffer.flush() == nil)
    }

    // MARK: Replacement

    @Test func textThatIsNotAnExtensionReplacesAtOnce() {
        var buffer = StreamRevealBuffer()
        _ = buffer.receive("Hello world")
        _ = buffer.tick()
        #expect(buffer.receive("Goodbye") == .replaced)
        #expect(buffer.isDrained)
        #expect(buffer.revealedText == "Goodbye")
        #expect(buffer.revealedUTF16 == 7)
        #expect(buffer.receive("Goodbye") == .unchanged)
        #expect(buffer.receive("Good") == .replaced)
    }
}

/// A small deterministic generator for reproducible chunking (shared by the stream tests).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
