import AVFoundation
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class MusicPlaybackIntegrationTests: XCTestCase {
    func testLocalMusicTrackIdentityIsStableAndBenchmarkable() {
        let tracks = (0 ..< 256).map { index in
            LocalMusicTrack(
                url: URL(fileURLWithPath: "/tmp/Spatial Music/Collection/../Collection/Track \(index).m4a"),
                title: "Track \(index)",
                artist: "Artist \(index % 8)",
                collection: "Collection",
                trackNumber: index + 1
            )
        }
        let identities = tracks.map(\.id)
        let expected = tracks.map { $0.url.standardizedFileURL.absoluteString }
        XCTAssertEqual(identities, expected)
        print("MUSIC_IDENTITY_GOLDEN=\(identities.prefix(4).joined(separator: "|"))")

        guard ProcessInfo.processInfo.environment["RUN_MUSIC_IDENTITY_BENCHMARK"] == "1" else { return }
        var samples: [Double] = []
        var checksum = 0
        let clock = ContinuousClock()
        for _ in 0 ..< 30 {
            let elapsed = clock.measure {
                for _ in 0 ..< 160 {
                    for track in tracks {
                        checksum &+= track.id.utf8.count
                    }
                }
            }
            let components = elapsed.components
            samples.append(
                Double(components.seconds) * 1_000
                    + Double(components.attoseconds) / 1_000_000_000_000_000
            )
        }
        samples.sort()
        let percentile: (Double) -> Double = { percentile in
            samples[min(samples.count - 1, Int(Double(samples.count - 1) * percentile))]
        }
        print(
            String(
                format: "MUSIC_IDENTITY_PERF_MS p50=%.3f p95=%.3f p99=%.3f checksum=%d",
                percentile(0.50),
                percentile(0.95),
                percentile(0.99),
                checksum
            )
        )
        XCTAssertGreaterThan(checksum, 0)
    }

    func testLocalLibraryDiscoversSupportedTracksAndInfersArtist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let album = root
            .appendingPathComponent("koalokangaroo22", isDirectory: true)
            .appendingPathComponent("Unknown Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([0]).write(to: album.appendingPathComponent("01 - Vibe Coder Drift [mlxet_DSu98].mp3"))
        try Data([0]).write(to: album.appendingPathComponent("02 - Push it live.wav"))
        try Data([0]).write(to: album.appendingPathComponent("notes.txt"))

        let tracks = LocalMusicLibrary.discoverTracks(in: [root, root])

        XCTAssertEqual(tracks.map(\.title), ["Vibe Coder Drift", "Push it live"])
        XCTAssertEqual(Set(tracks.map(\.artist)), ["koalokangaroo22"])
        XCTAssertEqual(Set(tracks.map(\.collection)), ["Unknown Album"])
        XCTAssertEqual(tracks.map(\.trackNumber), [1, 2])
        XCTAssertEqual(Set(tracks.map(\.url)).count, 2, "Overlapping roots must not duplicate tracks")
    }

    func testGeneratedCollectionRetainsTrackOrderAndModelCredit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let collection = root
            .appendingPathComponent("MiniMax-Music3", isDirectory: true)
            .appendingPathComponent("Flow State Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([0]).write(to: collection.appendingPathComponent("02 - Deep Compile.wav"))
        try Data([0]).write(to: collection.appendingPathComponent("01 - Neon Lock.wav"))

        let tracks = LocalMusicLibrary.discoverTracks(in: [root])

        XCTAssertEqual(tracks.map(\.title), ["Neon Lock", "Deep Compile"])
        XCTAssertEqual(tracks.map(\.trackNumber), [1, 2])
        XCTAssertEqual(Set(tracks.map(\.artist)), ["MiniMax-Music3"])
        XCTAssertEqual(Set(tracks.map(\.collection)), ["Flow State Originals"])
    }

    func testNewMusicNodeHasPlayableDefaultStation() {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence)

        let nodeID = store.addNode(kind: .music)
        let node = store.activeWorkspace.nodes.first(where: { $0.id == nodeID })

        XCTAssertEqual(node?.url, MusicStation.defaultURLString)
        XCTAssertEqual(MusicStation.matching(node?.url), .grooveSalad)
    }

    func testNativePlayerLoadsAndAdvancesRealAudioFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("tone.wav")
        try writeTone(to: audioURL, duration: 1.5)

        let playback = MusicPlaybackController()
        playback.load(audioURL)

        let becameReady = await waitUntil(timeout: 5) {
            playback.state == .ready
        }
        XCTAssertTrue(becameReady)

        playback.togglePlayback()

        let advanced = await waitUntil(timeout: 3) {
            playback.elapsed > 0.1
        }
        XCTAssertTrue(advanced)
        XCTAssertEqual(playback.loadedURL, audioURL)
        XCTAssertGreaterThan(playback.duration ?? 0, 1)
        playback.stop()
    }

    func testNativePlayerCanAutoplaySelectedTrack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("autoplay.wav")
        try writeTone(to: audioURL, duration: 1.5)

        let playback = MusicPlaybackController()
        playback.load(audioURL, autoplay: true)

        let started = await waitUntil(timeout: 5) {
            playback.state == .playing && playback.elapsed > 0.1
        }
        XCTAssertTrue(started, "Selected music should begin playing without a second click")
        playback.stop()
    }

    func testWaveformSamplerReadsRealAudioIntoNormalizedPeaks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("waveform.wav")
        try writeTone(to: audioURL, duration: 1.0)

        let samples = LocalWaveformSampler.samples(from: audioURL, count: 64)

        XCTAssertEqual(samples.count, 64)
        XCTAssertGreaterThan(samples.max() ?? 0, 0.99)
        XCTAssertTrue(samples.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testLiveStationConnectsAndPlaysWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_MEDIA_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_MEDIA_E2E=1 to verify the live radio service")
        }
        let stationURL = try XCTUnwrap(URL(string: MusicStation.grooveSalad.urlString))
        let playback = MusicPlaybackController()
        playback.load(stationURL)

        let connected = await waitUntil(timeout: 12) {
            playback.state == .ready
        }
        XCTAssertTrue(connected, "Live station did not become ready: \(playback.state)")

        playback.togglePlayback()
        let advanced = await waitUntil(timeout: 8) {
            playback.elapsed > 0.1
        }
        XCTAssertTrue(advanced, "Live station connected but did not advance")
        playback.stop()
    }

    private func writeTone(to url: URL, duration: Double) throws {
        let sampleRate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0 ..< Int(frameCount) {
            channel[frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate) * 0.12)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
