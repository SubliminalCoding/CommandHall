import SwiftUI

/// A live YouTube chat tile. It loads YouTube's popout live-chat page in a web
/// view (reusing the signed-in session), so messages from the active broadcast
/// appear right inside the workspace. The stream is identified by a video ID,
/// which is either auto-detected from a channel handle or pasted in by hand and
/// then persisted as the node's `url` (the full popout chat address).
struct LiveChatPane: View {
    let node: WorkspaceNode
    let onNavigate: (String) -> Void
    let onRefresh: () -> Void

    @AppStorage("youtubeLiveChatChannel") private var channelHandle = "BilbroSwagginz"
    @AppStorage("youtubeLiveChatLastVideoID") private var lastVideoID = ""

    @State private var manualEntry = ""
    @State private var isResolving = false
    @State private var statusMessage: String?
    @State private var chatState = WebPreviewState.idle

    private var currentVideoID: String? {
        YouTubeLive.videoID(from: node.url ?? "")
    }

    var body: some View {
        Group {
            if let videoID = currentVideoID {
                chatView(videoID: videoID)
            } else {
                setupView
            }
        }
        .accessibilityLabel("YouTube live chat")
    }

    // MARK: - Connected chat

    private func chatView(videoID: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(chatState.isLoading ? Color.orange : Color.red)
                    .frame(width: 7, height: 7)
                Text("LIVE CHAT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                Text(videoID)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                iconButton("arrow.clockwise", label: "Reload chat", action: onRefresh)
                iconButton("rectangle.on.rectangle", label: "Change stream") {
                    onNavigate("")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.42))
            .overlay(alignment: .bottom) { Divider().opacity(0.25) }

            WebPreview(
                urlString: YouTubeLive.chatURL(videoID: videoID),
                revision: node.revision,
                state: $chatState
            )
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.red)
                Text("Connect your live chat")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Auto-detect the current broadcast, or paste a stream link.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("@")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("channel handle", text: $channelHandle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit(detectLive)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.1)))

                Button(action: detectLive) {
                    HStack(spacing: 6) {
                        if isResolving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        Text(isResolving ? "Looking for the stream…" : "Detect live stream")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isResolving || channelHandle.trimmingCharacters(in: .whitespaces).isEmpty)

                if YouTubeLive.isValidID(lastVideoID) {
                    Button("Reconnect last stream") { connect(lastVideoID) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 300)

            HStack(spacing: 8) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                Text("or").font(.system(size: 10)).foregroundStyle(.tertiary)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
            .frame(maxWidth: 300)

            HStack(spacing: 6) {
                TextField("Paste a YouTube live URL or video ID", text: $manualEntry)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(loadManual)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.1)))
                Button("Load", action: loadManual)
                    .disabled(YouTubeLive.videoID(from: manualEntry) == nil)
            }
            .frame(maxWidth: 300)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 300)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func connect(_ videoID: String) {
        guard YouTubeLive.isValidID(videoID) else { return }
        lastVideoID = videoID
        statusMessage = nil
        onNavigate(YouTubeLive.chatURL(videoID: videoID))
    }

    private func loadManual() {
        guard let videoID = YouTubeLive.videoID(from: manualEntry) else {
            statusMessage = "That doesn't look like a YouTube video link or ID."
            return
        }
        manualEntry = ""
        connect(videoID)
    }

    private func detectLive() {
        let handle = channelHandle.trimmingCharacters(in: CharacterSet(charactersIn: " @\n\t"))
        guard !handle.isEmpty else { return }
        isResolving = true
        statusMessage = nil
        Task {
            let resolved = await YouTubeLive.resolveLiveVideoID(channelHandle: handle)
            await MainActor.run {
                isResolving = false
                if let resolved {
                    connect(resolved)
                } else {
                    statusMessage = "Couldn't find a live stream for @\(handle). Start the broadcast, or paste the link below."
                }
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.05), in: Circle())
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Helpers for turning stream links/handles into a YouTube popout live-chat URL.
enum YouTubeLive {
    /// The popout live-chat page — the same surface OBS uses as a browser source.
    static func chatURL(videoID: String) -> String {
        "https://www.youtube.com/live_chat?is_popout=1&v=\(videoID)"
    }

    static func isValidID(_ candidate: String) -> Bool {
        candidate.count == 11 && candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Extract an 11-character video ID from a raw ID, a watch/live/embed/youtu.be
    /// URL, a `live_chat?v=` URL, or arbitrary text containing `"videoId":"…"`.
    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isValidID(trimmed) { return trimmed }

        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let comps = URLComponents(string: urlString) {
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, isValidID(v) {
                return v
            }
            let parts = comps.path.split(separator: "/").map(String.init)
            if let host = comps.host, host.contains("youtu.be"), let first = parts.first, isValidID(first) {
                return first
            }
            if let idx = parts.firstIndex(where: { ["live", "embed", "shorts", "v"].contains($0) }),
               idx + 1 < parts.count, isValidID(parts[idx + 1]) {
                return parts[idx + 1]
            }
        }
        return capture(#""videoId":"([A-Za-z0-9_-]{11})""#, in: trimmed)
    }

    /// Best-effort: fetch a channel's `/live` page and read the currently-live
    /// video ID from its canonical link. Returns nil when the channel is offline.
    static func resolveLiveVideoID(channelHandle: String) async -> String? {
        let handle = channelHandle.trimmingCharacters(in: CharacterSet(charactersIn: " @\n\t"))
        guard !handle.isEmpty,
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.youtube.com/@\(encoded)/live") else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            // When the channel is live, the canonical link resolves to the live watch URL.
            if let id = capture(#"canonical"\s+href="https://www\.youtube\.com/watch\?v=([A-Za-z0-9_-]{11})"#, in: html) {
                return id
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Return the first capture group of `pattern` in `text`.
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
