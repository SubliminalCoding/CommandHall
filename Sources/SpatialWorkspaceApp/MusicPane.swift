import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LocalMusicTrack: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let title: String
    let artist: String
    let collection: String
    let trackNumber: Int?

    init(
        url: URL,
        title: String,
        artist: String,
        collection: String,
        trackNumber: Int?
    ) {
        id = url.standardizedFileURL.absoluteString
        self.url = url
        self.title = title
        self.artist = artist
        self.collection = collection
        self.trackNumber = trackNumber
    }
}

enum LocalWaveformSampler {
    nonisolated static func samples(from url: URL, count: Int = 96) -> [Double] {
        guard count > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = max(1, file.length)
        let capacity = AVAudioFrameCount(min(16_384, totalFrames))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return [] }

        var peaks = Array(repeating: 0.0, count: count)
        var frameOffset: AVAudioFramePosition = 0

        while frameOffset < file.length {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: capacity)) != nil, buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else { break }
            let channelCount = Int(buffer.format.channelCount)

            for frame in 0 ..< Int(buffer.frameLength) {
                var amplitude = 0.0
                for channel in 0 ..< channelCount {
                    amplitude = max(amplitude, Double(abs(channels[channel][frame])))
                }
                let absoluteFrame = frameOffset + AVAudioFramePosition(frame)
                let bin = min(count - 1, Int(absoluteFrame * AVAudioFramePosition(count) / totalFrames))
                peaks[bin] = max(peaks[bin], amplitude)
            }
            frameOffset += AVAudioFramePosition(buffer.frameLength)
        }

        guard let maximum = peaks.max(), maximum > 0 else { return peaks }
        return peaks.map { pow($0 / maximum, 0.62) }
    }
}

@MainActor
final class LocalMusicLibrary: ObservableObject {
    @Published private(set) var tracks: [LocalMusicTrack] = []
    @Published private(set) var isLoading = false

    private var hasLoaded = false

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let roots = Self.defaultRoots
        Task {
            let discovered = await Task.detached(priority: .utility) {
                Self.discoverTracks(in: roots)
            }.value
            tracks = discovered
            isLoading = false
            hasLoaded = true
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func add(_ urls: [URL]) {
        let imported = urls.compactMap(Self.track(for:))
        var merged = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for track in imported { merged[track.id] = track }
        tracks = merged.values.sorted(by: Self.trackSort)
    }

    nonisolated static func discoverTracks(in roots: [URL], limit: Int = 1_000) -> [LocalMusicTrack] {
        var discovered: [String: LocalMusicTrack] = [:]
        let fileManager = FileManager.default

        for root in roots where discovered.count < limit {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isReadableKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard discovered.count < limit else { break }
                guard let track = track(for: url) else { continue }
                discovered[track.id] = track
            }
        }

        return discovered.values.sorted(by: trackSort)
    }

    nonisolated static func track(for url: URL) -> LocalMusicTrack? {
        let supportedExtensions = Set(["aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "wav"])
        guard url.isFileURL, supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]).isRegularFile) == true else {
            return nil
        }

        let fileTitle = url.deletingPathExtension().lastPathComponent
        let albumDirectory = url.deletingLastPathComponent()
        let artistDirectory = albumDirectory.deletingLastPathComponent().lastPathComponent
        let genericDirectoryNames = Set(["", "music", "media.localized", "unknown artist"])
        let artist = genericDirectoryNames.contains(artistDirectory.lowercased()) ? "Local track" : artistDirectory
        return LocalMusicTrack(
            url: url.standardizedFileURL,
            title: cleanTitle(fileTitle),
            artist: artist,
            collection: albumDirectory.lastPathComponent,
            trackNumber: trackNumber(in: fileTitle)
        )
    }

    private static let defaultRoots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
        ]
    }()

    nonisolated private static func trackSort(_ lhs: LocalMusicTrack, _ rhs: LocalMusicTrack) -> Bool {
        let artistOrder = lhs.artist.localizedStandardCompare(rhs.artist)
        if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
        let collectionOrder = lhs.collection.localizedStandardCompare(rhs.collection)
        if collectionOrder != .orderedSame { return collectionOrder == .orderedAscending }
        switch (lhs.trackNumber, rhs.trackNumber) {
        case let (leftNumber?, rightNumber?) where leftNumber != rightNumber: return leftNumber < rightNumber
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    nonisolated private static func trackNumber(in fileTitle: String) -> Int? {
        guard fileTitle.count > 5 else { return nil }
        let prefix = fileTitle.prefix(5)
        guard prefix.dropFirst(2) == " - " else { return nil }
        return Int(prefix.prefix(2))
    }

    nonisolated private static func cleanTitle(_ fileTitle: String) -> String {
        var title = fileTitle
        if trackNumber(in: title) != nil { title.removeFirst(5) }
        if title.hasSuffix("]"), let sourceID = title.range(of: " [", options: .backwards) {
            title.removeSubrange(sourceID.lowerBound...)
        }
        for prefix in ["StreamBeats Originals - ", "StreamBeats - "] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
        }
        for marker in [" - (Official", " (Official"] {
            if let range = title.range(of: marker, options: .caseInsensitive) {
                title.removeSubrange(range.lowerBound...)
            }
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"＂")))
    }
}

enum MusicStation: String, CaseIterable, Identifiable {
    case grooveSalad
    case droneZone
    case secretAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grooveSalad: "Groove Salad"
        case .droneZone: "Drone Zone"
        case .secretAgent: "Secret Agent"
        }
    }

    var subtitle: String {
        switch self {
        case .grooveSalad: "Ambient and downtempo"
        case .droneZone: "Atmospheric textures"
        case .secretAgent: "Cinematic lounge"
        }
    }

    var urlString: String {
        switch self {
        case .grooveSalad: "https://ice2.somafm.com/groovesalad-128-mp3"
        case .droneZone: "https://ice2.somafm.com/dronezone-128-mp3"
        case .secretAgent: "https://ice2.somafm.com/secretagent-128-mp3"
        }
    }

    static let defaultURLString = MusicStation.grooveSalad.urlString

    static func matching(_ urlString: String?) -> MusicStation? {
        allCases.first { $0.urlString == urlString }
    }
}

@MainActor
final class MusicPlaybackController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case playing
        case paused
        case ended
        case failed(String)

        var label: String {
            switch self {
            case .idle: "No source"
            case .loading: "Connecting"
            case .ready: "Ready"
            case .playing: "Playing"
            case .paused: "Paused"
            case .ended: "Finished"
            case .failed: "Playback failed"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration: Double?
    @Published var volume = 0.75 {
        didSet { player?.volume = Float(volume) }
    }

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var playWhenReady = false
    private(set) var loadedURL: URL?

    var isPlaying: Bool { state == .playing }
    var canPlay: Bool {
        switch state {
        case .idle, .failed: false
        case .loading, .ready, .playing, .paused, .ended: true
        }
    }

    func load(_ url: URL?, autoplay: Bool = false) {
        guard loadedURL != url || player == nil else {
            if autoplay {
                player?.play()
                state = .playing
            }
            return
        }
        tearDownPlayer()
        loadedURL = url
        guard let url else {
            state = .idle
            return
        }

        state = .loading
        elapsed = 0
        duration = nil
        playWhenReady = autoplay

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.volume = Float(volume)
        player = nextPlayer

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .unknown:
                    self.state = .loading
                case .readyToPlay:
                    self.updateDuration(from: item)
                    if self.playWhenReady {
                        self.playWhenReady = false
                        self.player?.play()
                    } else if self.state == .loading {
                        self.state = .ready
                    }
                case .failed:
                    self.playWhenReady = false
                    self.state = .failed(item.error?.localizedDescription ?? "The audio source could not be opened.")
                @unknown default:
                    self.state = .failed("The player returned an unknown state.")
                }
            }
        }

        timeControlObservation = nextPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing: self.state = .playing
                case .waitingToPlayAtSpecifiedRate:
                    if self.state != .playing { self.state = .loading }
                case .paused:
                    if self.state == .playing { self.state = .paused }
                @unknown default: break
                }
            }
        }

        timeObserver = nextPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.seconds.isFinite else { return }
            Task { @MainActor in
                self?.elapsed = max(0, time.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.state = .ended }
        }
    }

    func togglePlayback() {
        guard let player, canPlay else { return }
        if isPlaying {
            player.pause()
            state = .paused
            return
        }
        if state == .ended { player.seek(to: .zero) }
        player.play()
        state = .playing
    }

    func seek(to seconds: Double) {
        guard let duration, duration.isFinite else { return }
        let target = min(duration, max(0, seconds))
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
    }

    func stop() {
        player?.pause()
        if state == .playing { state = .paused }
    }

    private func updateDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        duration = seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func tearDownPlayer() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation = nil
        timeControlObservation = nil
        timeObserver = nil
        endObserver = nil
        player = nil
        playWhenReady = false
    }

    deinit {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

enum LibraryRoute: Hashable {
    case chooser
    case radio
    case playlist(String)
}

struct MusicPane: View {
    let theme: WorkspaceTheme
    let urlString: String?
    let onChoose: (String) -> Void

    @StateObject private var playback = MusicPlaybackController()
    @StateObject private var library = LocalMusicLibrary()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLibraryPresented = false
    @State private var searchText = ""
    @State private var libraryRoute: LibraryRoute = .chooser
    @State private var autoplayNextLoad = false
    @State private var waveformSamples: [Double] = []

    var body: some View {
        ZStack {
            FlowPlayerBackdrop(theme: theme, seed: artworkSeed, isActive: playback.isPlaying && !reduceMotion)

            VStack(alignment: .leading, spacing: 10) {
                playerHeader

                HStack(spacing: 14) {
                    FlowArtwork(theme: theme, seed: artworkSeed, isActive: playback.isPlaying && !reduceMotion)
                        .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayTitle)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(displaySubtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            metadataPill(collectionLabel, icon: selectedStation == nil ? "square.stack.fill" : "dot.radiowaves.left.and.right")
                            if isGeneratedOriginal {
                                metadataPill("MINIMAX-MUSIC3", icon: "sparkles")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = failureMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .accessibilityLabel("Playback error. \(message)")
                }

                playbackTimeline
                transportControls
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: theme)
        .onAppear {
            library.loadIfNeeded()
            configurePlayer()
            loadWaveform()
        }
        .onChange(of: urlString) { _, _ in
            configurePlayer()
            loadWaveform()
        }
        .onChange(of: playback.state) { _, state in
            if state == .ended { advance(by: 1, autoplay: true) }
        }
        .onDisappear { playback.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Music player")
    }

    private var playerHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: stateColor.opacity(playback.isPlaying ? 0.8 : 0), radius: 5)
                Text(playback.state.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.72))

            Spacer()

            if canNavigateLocalLibrary {
                Text("\(currentTrackPosition) / \(navigationTracks.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.44))
            }

            Button {
                isLibraryPresented.toggle()
            } label: {
                Label("Library", systemImage: "music.note.list")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.11)))
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .popover(isPresented: $isLibraryPresented, arrowEdge: .top) {
                musicLibrary
            }
            .accessibilityLabel("Choose music source")
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Image(systemName: playback.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 14)
            Slider(value: $playback.volume, in: 0 ... 1)
                .tint(.white.opacity(0.72))
                .frame(maxWidth: 94)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(playback.volume * 100)) percent")

            Spacer(minLength: 5)

            transportButton(symbol: "backward.end.fill", label: "Previous track", enabled: canNavigateLocalLibrary) {
                advance(by: -1, autoplay: true)
            }

            Button(action: playback.togglePlayback) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(playback.canPlay ? Color.black.opacity(0.88) : .secondary)
                    .offset(x: playback.isPlaying ? 0 : 1)
                    .frame(width: 43, height: 43)
                    .background(playback.canPlay ? Color.white : .white.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7)))
                    .shadow(color: playback.isPlaying ? accentColor.opacity(0.55) : .black.opacity(0.22), radius: 14, y: 4)
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .disabled(!playback.canPlay)
            .accessibilityLabel(playback.isPlaying ? "Pause audio" : "Play audio")

            transportButton(symbol: "forward.end.fill", label: "Next track", enabled: canNavigateLocalLibrary) {
                advance(by: 1, autoplay: true)
            }

            Spacer(minLength: 5)

            Image(systemName: playback.isPlaying ? "waveform.badge.magnifyingglass" : "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor.opacity(playback.isPlaying ? 0.95 : 0.38))
                .symbolEffect(.variableColor.iterative, isActive: playback.isPlaying && !reduceMotion)
                .frame(width: 24)
        }
    }

    private func transportButton(
        symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .white.opacity(0.82) : .white.opacity(0.22))
                .frame(width: 32, height: 32)
                .background(.white.opacity(enabled ? 0.065 : 0.025), in: Circle())
                .overlay(Circle().stroke(.white.opacity(enabled ? 0.09 : 0.035)))
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func metadataPill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(.black.opacity(0.2), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08)))
    }

    private var musicLibrary: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [WorkspaceVisualStyle.cyan.opacity(0.7), Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound Library")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Choose a flow, track, or live station")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if library.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(library.tracks.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(.white.opacity(0.06), in: Capsule())
                        .help("\(library.tracks.count) tracks on this Mac")
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a track, collection, or artist", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search music library")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.08)))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if isSearching {
                        librarySectionLabel("Search results")
                        if searchResults.isEmpty, !library.isLoading {
                            libraryEmptyState
                        } else {
                            ForEach(searchResults) { track in
                                sourceRow(
                                    title: track.title,
                                    subtitle: track.collection,
                                    icon: "music.note",
                                    isSelected: selectedLocalTrack?.id == track.id
                                ) {
                                    selectSource(track.url.absoluteString, autoplay: true)
                                }
                            }
                        }
                    } else {
                        switch libraryRoute {
                        case .chooser:
                            if let hero = heroCollection {
                                collectionHero(
                                    title: hero.name,
                                    subtitle: heroSubtitle(for: hero.name, count: hero.tracks.count),
                                    tracks: hero.tracks
                                )
                                .padding(.bottom, 4)
                            }

                            librarySectionLabel("Playlists")
                            playlistChooserRow(
                                title: "Live radio",
                                subtitle: "\(MusicStation.allCases.count) stations",
                                icon: "dot.radiowaves.left.and.right"
                            ) {
                                libraryRoute = .radio
                            }
                            if library.tracks.isEmpty, !library.isLoading {
                                libraryEmptyState
                            } else {
                                ForEach(localCollections, id: \.name) { group in
                                    playlistChooserRow(
                                        title: group.name,
                                        subtitle: "\(group.tracks.count) \(group.tracks.count == 1 ? "track" : "tracks")",
                                        icon: sectionIcon(for: group.tracks)
                                    ) {
                                        libraryRoute = .playlist(group.name)
                                    }
                                }
                            }

                        case .radio:
                            libraryBackHeader("Live radio")
                            ForEach(MusicStation.allCases) { station in
                                sourceRow(
                                    title: station.title,
                                    subtitle: station.subtitle,
                                    icon: "dot.radiowaves.left.and.right",
                                    isSelected: selectedStation == station
                                ) {
                                    selectSource(station.urlString, autoplay: true)
                                }
                            }

                        case let .playlist(name):
                            libraryBackHeader(name)
                            if playlistTracks(name).isEmpty {
                                libraryEmptyState
                            } else {
                                ForEach(playlistTracks(name)) { track in
                                    sourceRow(
                                        title: track.title,
                                        subtitle: track.artist,
                                        icon: sectionIcon(for: playlistTracks(name)),
                                        isSelected: selectedLocalTrack?.id == track.id
                                    ) {
                                        selectSource(track.url.absoluteString, autoplay: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Choose songs…", action: chooseFiles)
                Button {
                    library.refresh()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button("Done") {
                    isLibraryPresented = false
                    libraryRoute = .chooser
                }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 410, height: 510)
        .background(
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.1), Color(red: 0.015, green: 0.022, blue: 0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func collectionHero(title: String, subtitle: String, tracks: [LocalMusicTrack]) -> some View {
        Button {
            guard let first = tracks.first else { return }
            selectSource(first.url.absoluteString, autoplay: true)
        } label: {
            HStack(spacing: 11) {
                FlowArtwork(
                    theme: theme,
                    seed: title.unicodeScalars.reduce(9) { $0 &* 31 &+ Int($1.value) },
                    isActive: false
                )
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.58))
                    Text("\(tracks.count) TRACKS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(WorkspaceVisualStyle.accent.opacity(0.85))
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(width: 32, height: 32)
                    .background(.white, in: Circle())
            }
            .padding(10)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.1)))
        }
        .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 13))
    }

    private func playlistTracks(_ name: String) -> [LocalMusicTrack] {
        localCollections.first { $0.name == name }?.tracks ?? []
    }

    private func playlistChooserRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(WorkspaceVisualStyle.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func libraryBackHeader(_ title: String) -> some View {
        Button {
            libraryRoute = .chooser
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func librarySectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
    }

    private func sourceRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? WorkspaceVisualStyle.accent : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(WorkspaceVisualStyle.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? WorkspaceVisualStyle.accent.opacity(0.1) : .white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var playbackTimeline: some View {
        if let duration = playback.duration {
            VStack(spacing: 2) {
                FlowWaveform(
                    samples: waveformSamples,
                    progress: duration > 0 ? playback.elapsed / duration : 0,
                    isActive: playback.isPlaying && !reduceMotion,
                    accent: accentColor,
                    seed: artworkSeed
                ) { fraction in
                    playback.seek(to: fraction * duration)
                }
                .frame(height: 37)
                .accessibilityElement()
                .accessibilityLabel("Track waveform")
                .accessibilityValue("\(timeLabel(playback.elapsed)) of \(timeLabel(duration))")
                .accessibilityAdjustableAction { direction in
                    let offset = direction == .increment ? 5.0 : -5.0
                    playback.seek(to: playback.elapsed + offset)
                }

                HStack {
                    Text(timeLabel(playback.elapsed))
                    Spacer()
                    Text("−\(timeLabel(max(0, duration - playback.elapsed)))")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            }
        } else {
            VStack(spacing: 2) {
                FlowWaveform(
                    samples: [],
                    progress: playback.isPlaying ? 0.52 : 0,
                    isActive: playback.isPlaying && !reduceMotion,
                    accent: accentColor,
                    seed: artworkSeed,
                    onSeek: nil
                )
                .frame(height: 37)
                .accessibilityHidden(true)

                HStack {
                    Label(
                        selectedStation == nil ? "Waiting for track information" : "LIVE RADIO",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    Spacer()
                    if playback.state == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.65)
                .foregroundStyle(selectedStation == nil ? .white.opacity(0.42) : accentColor)
            }
        }
    }

    private var displayTitle: String {
        selectedLocalTrack?.title ?? selectedStation?.title ?? trackName
    }

    private var displaySubtitle: String {
        selectedLocalTrack?.artist ?? selectedStation?.subtitle ?? "Local audio"
    }

    private var collectionLabel: String {
        selectedLocalTrack?.collection.uppercased() ?? (selectedStation == nil ? "LOCAL AUDIO" : "LIVE RADIO")
    }

    private var isGeneratedOriginal: Bool {
        guard let track = selectedLocalTrack else { return false }
        return track.collection.localizedCaseInsensitiveContains("flow state")
            || track.artist.localizedCaseInsensitiveContains("minimax")
    }

    private var artworkSeed: Int {
        displayTitle.unicodeScalars.reduce(17) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    }

    private var accentColor: Color {
        FlowPalette.colors(for: artworkSeed, theme: theme).accent
    }

    private var currentTrackPosition: Int {
        guard let selectedLocalTrack,
              let index = navigationTracks.firstIndex(where: { $0.id == selectedLocalTrack.id }) else { return 0 }
        return index + 1
    }

    private var resolvedURLString: String {
        urlString ?? MusicStation.defaultURLString
    }

    private var selectedStation: MusicStation? {
        MusicStation.matching(resolvedURLString)
    }

    private var selectedLocalTrack: LocalMusicTrack? {
        guard let selectedURL = URL(string: resolvedURLString), selectedURL.isFileURL else { return nil }
        let selectedID = selectedURL.standardizedFileURL.absoluteString
        return library.tracks.first { $0.id == selectedID }
    }

    // Collections pinned to the top of the library, in this order. Everything
    // else follows alphabetically. The first present pinned collection also
    // becomes the featured hero card.
    private static let pinnedCollections = [
        "MiniMax Sessions (Full Playlist)",
        "Flow State Originals",
        "CommandHall Focus",
    ]

    private var libraryEmptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: searchText.isEmpty ? "music.note" : "magnifyingglass")
                .font(.system(size: 19))
            Text(searchText.isEmpty ? "No local tracks found" : "No matching tracks")
                .font(.system(size: 11, weight: .semibold))
            if searchText.isEmpty {
                Text("Choose songs below to add them for this session.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .foregroundStyle(.secondary)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [LocalMusicTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return library.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.collection.localizedCaseInsensitiveContains(query)
        }
    }

    // Every local folder becomes its own playlist section, pinned collections
    // first, then alphabetical. Tracks within a section follow their NN- prefix.
    private var localCollections: [(name: String, tracks: [LocalMusicTrack])] {
        func rank(_ name: String) -> Int {
            Self.pinnedCollections.firstIndex { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
                ?? Self.pinnedCollections.count
        }
        return Dictionary(grouping: library.tracks, by: { $0.collection })
            .map { (name: $0.key, tracks: Self.collectionSorted($0.value)) }
            .sorted { lhs, rhs in
                let lr = rank(lhs.name), rr = rank(rhs.name)
                if lr != rr { return lr < rr }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var heroCollection: (name: String, tracks: [LocalMusicTrack])? {
        guard let first = localCollections.first,
              Self.pinnedCollections.contains(where: { $0.localizedCaseInsensitiveCompare(first.name) == .orderedSame })
        else { return nil }
        return first
    }

    private static func collectionSorted(_ tracks: [LocalMusicTrack]) -> [LocalMusicTrack] {
        tracks.sorted { lhs, rhs in
            switch (lhs.trackNumber, rhs.trackNumber) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func sectionIcon(for tracks: [LocalMusicTrack]) -> String {
        tracks.first?.artist.localizedCaseInsensitiveContains("MiniMax") == true ? "sparkles" : "music.note"
    }

    private func heroSubtitle(for name: String, count: Int) -> String {
        if name.localizedCaseInsensitiveContains("Full Playlist") {
            return "All generated sessions · plays in order"
        }
        return "\(count) tracks · MiniMax-Music3"
    }

    private var navigationTracks: [LocalMusicTrack] {
        guard let selectedLocalTrack else { return library.tracks }
        let collectionTracks = library.tracks.filter { $0.collection == selectedLocalTrack.collection }
        return collectionTracks.isEmpty ? library.tracks : collectionTracks
    }

    private var canNavigateLocalLibrary: Bool {
        selectedLocalTrack != nil && navigationTracks.count > 1
    }

    private var trackName: String {
        if let selectedStation { return selectedStation.title }
        guard let url = URL(string: resolvedURLString) else { return "No track" }
        return url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    }

    private var stateColor: Color {
        switch playback.state {
        case .playing: .green
        case .loading: .yellow
        case .failed: .orange
        case .idle: .secondary
        case .ready, .paused, .ended: WorkspaceVisualStyle.cyan
        }
    }

    private var failureMessage: String? {
        if case let .failed(message) = playback.state { return message }
        return nil
    }

    private func configurePlayer() {
        let shouldAutoplay = autoplayNextLoad
        autoplayNextLoad = false
        playback.load(URL(string: resolvedURLString), autoplay: shouldAutoplay)
    }

    private func loadWaveform() {
        guard let url = URL(string: resolvedURLString), url.isFileURL else {
            waveformSamples = []
            return
        }
        let expectedURL = url.standardizedFileURL
        waveformSamples = []
        Task {
            let samples = await Task.detached(priority: .utility) {
                LocalWaveformSampler.samples(from: expectedURL)
            }.value
            guard URL(string: resolvedURLString)?.standardizedFileURL == expectedURL else { return }
            waveformSamples = samples
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Add Songs"
        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        library.add(panel.urls)
        selectSource(first.absoluteString, autoplay: true)
    }

    private func selectSource(_ source: String, autoplay: Bool) {
        autoplayNextLoad = autoplay
        onChoose(source)
        isLibraryPresented = false
    }

    private func advance(by offset: Int, autoplay: Bool) {
        let tracks = navigationTracks
        guard !tracks.isEmpty else { return }
        let currentIndex = selectedLocalTrack.flatMap { selected in
            tracks.firstIndex(where: { $0.id == selected.id })
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + tracks.count) % tracks.count
        selectSource(tracks[nextIndex].url.absoluteString, autoplay: autoplay)
    }

    private func timeLabel(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct FlowWaveform: View {
    let samples: [Double]
    let progress: Double
    let isActive: Bool
    let accent: Color
    let seed: Int
    let onSeek: ((Double) -> Void)?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    let barCount = max(28, min(96, Int(size.width / 4)))
                    let spacing = size.width / CGFloat(barCount)
                    let barWidth = max(1.4, min(2.7, spacing * 0.55))
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 4.8

                    for index in 0 ..< barCount {
                        let fraction = (Double(index) + 0.5) / Double(barCount)
                        let baseAmplitude = amplitude(at: fraction, index: index)
                        let motion = isActive ? 0.91 + 0.09 * sin(phase + Double(index) * 0.58) : 1
                        let height = max(3, CGFloat(baseAmplitude * motion) * (size.height - 5))
                        let x = (CGFloat(index) + 0.5) * spacing
                        let rect = CGRect(x: x - barWidth / 2, y: (size.height - height) / 2, width: barWidth, height: height)
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        let isPlayed = fraction <= min(1, max(0, progress))
                        let headDistance = abs(fraction - progress)

                        if isActive, headDistance < 0.045 {
                            context.drawLayer { layer in
                                layer.addFilter(.shadow(color: accent.opacity(0.8), radius: 5))
                                layer.fill(path, with: .color(accent.opacity(0.8)))
                            }
                        }
                        context.fill(
                            path,
                            with: .color(isPlayed ? accent.opacity(0.9) : .white.opacity(0.18))
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in seek(to: value.location.x, width: geometry.size.width) }
                        .onEnded { value in seek(to: value.location.x, width: geometry.size.width) }
                )
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.07)))
    }

    private func amplitude(at fraction: Double, index: Int) -> Double {
        guard !samples.isEmpty else {
            let variation = sin(Double(index + seed % 17) * 0.71) * 0.2
            let detail = sin(Double(index + seed % 11) * 1.93) * 0.12
            return min(0.92, max(0.16, 0.46 + variation + detail))
        }
        let sampleIndex = min(samples.count - 1, Int(fraction * Double(samples.count)))
        return min(1, max(0.06, samples[sampleIndex]))
    }

    private func seek(to x: CGFloat, width: CGFloat) {
        guard let onSeek, width > 0 else { return }
        onSeek(min(1, max(0, Double(x / width))))
    }
}

private enum FlowPalette {
    struct Colors {
        let primary: Color
        let secondary: Color
        let accent: Color
    }

    static func colors(for seed: Int, theme: WorkspaceTheme) -> Colors {
        let base: Colors
        switch theme {
        case .nocturne:
            base = Colors(
                primary: Color(red: 0.22, green: 0.66, blue: 0.42),
                secondary: Color(red: 0.07, green: 0.37, blue: 0.42),
                accent: theme.accent
            )
        case .aurora:
            base = Colors(
                primary: Color(red: 0.18, green: 0.88, blue: 0.7),
                secondary: Color(red: 0.48, green: 0.22, blue: 0.94),
                accent: theme.accent
            )
        case .cosmos:
            base = Colors(
                primary: Color(red: 0.48, green: 0.28, blue: 0.94),
                secondary: Color(red: 0.84, green: 0.18, blue: 0.62),
                accent: theme.accent
            )
        case .moonrise:
            base = Colors(
                primary: Color(red: 0.22, green: 0.58, blue: 0.96),
                secondary: Color(red: 0.1, green: 0.73, blue: 0.84),
                accent: theme.accent
            )
        case .ember:
            base = Colors(
                primary: Color(red: 0.96, green: 0.31, blue: 0.12),
                secondary: Color(red: 0.7, green: 0.08, blue: 0.22),
                accent: theme.accent
            )
        case .abyss:
            base = Colors(
                primary: Color(red: 0.02, green: 0.68, blue: 0.67),
                secondary: Color(red: 0.02, green: 0.27, blue: 0.62),
                accent: theme.accent
            )
        case .tempest:
            base = Colors(
                primary: Color(red: 0.22, green: 0.48, blue: 0.98),
                secondary: Color(red: 0.48, green: 0.28, blue: 0.82),
                accent: theme.accent
            )
        case .skyIsles:
            base = Colors(
                primary: Color(red: 0.96, green: 0.52, blue: 0.2),
                secondary: Color(red: 0.72, green: 0.2, blue: 0.42),
                accent: theme.accent
            )
        }

        guard !seed.isMultiple(of: 2) else { return base }
        return Colors(primary: base.secondary, secondary: base.primary, accent: base.accent)
    }
}

private struct FlowPlayerBackdrop: View {
    let theme: WorkspaceTheme
    let seed: Int
    let isActive: Bool

    var body: some View {
        let palette = FlowPalette.colors(for: seed, theme: theme)
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    LinearGradient(
                        colors: [Color.black.opacity(0.32), Color(red: 0.018, green: 0.025, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(palette.primary.opacity(0.31))
                        .frame(width: width * 0.72)
                        .blur(radius: 54)
                        .offset(
                            x: width * CGFloat(sin(time * 0.11 + Double(seed % 7))) * 0.2,
                            y: -height * 0.25 + height * CGFloat(cos(time * 0.09)) * 0.12
                        )

                    Circle()
                        .fill(palette.secondary.opacity(0.25))
                        .frame(width: width * 0.62)
                        .blur(radius: 58)
                        .offset(
                            x: width * 0.34 + width * CGFloat(cos(time * 0.08)) * 0.14,
                            y: height * 0.28 + height * CGFloat(sin(time * 0.1)) * 0.12
                        )

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct FlowArtwork: View {
    let theme: WorkspaceTheme
    let seed: Int
    let isActive: Bool

    var body: some View {
        let palette = FlowPalette.colors(for: seed, theme: theme)
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.primary, palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 1)
                    .padding(12)
                    .rotationEffect(.degrees(isActive ? time * 12 : 18))

                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        AngularGradient(colors: [.clear, .white.opacity(0.78), .clear], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .padding(20)
                    .rotationEffect(.degrees(isActive ? -time * 19 : -36))

                Circle()
                    .fill(.black.opacity(0.34))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white.opacity(0.22)))

                Circle()
                    .fill(palette.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: palette.accent.opacity(0.85), radius: 8)
            }
            .shadow(color: palette.primary.opacity(isActive ? 0.34 : 0.16), radius: 18, y: 7)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.2)))
        .accessibilityHidden(true)
    }
}
