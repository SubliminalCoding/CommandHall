import SwiftUI

struct VoiceTranscriptionSettingsView: View {
    @Binding var isPresented: Bool
    @State private var apiKey = ""
    @State private var language = "en"
    @State private var prompt = VoiceTranscriptionPreferences.defaultPrompt
    @State private var hasSavedKey = VoiceCredentialStore.apiKey() != nil
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Voice Transcription")
                        .font(.title2.weight(.semibold))
                    Text("Uses the configured HQ Whisper endpoint first, with Groq as an optional fallback.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Optional Groq fallback key").font(.headline)
                    Spacer()
                    Label(hasSavedKey ? "Saved in Keychain" : "Not configured", systemImage: hasSavedKey ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(hasSavedKey ? Color.green : Color.orange)
                }
                SecureField(hasSavedKey ? "Enter a replacement key" : "gsk_…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Link("Create a Groq API key", destination: URL(string: "https://console.groq.com/keys")!)
                    Spacer()
                    if hasSavedKey {
                        Button("Remove", role: .destructive, action: removeKey)
                    }
                    Button("Save Key", action: saveKey)
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Language").foregroundStyle(.secondary)
                    TextField("en", text: $language).textFieldStyle(.roundedBorder)
                }
                GridRow(alignment: .top) {
                    Text("Recognition hints").foregroundStyle(.secondary).padding(.top, 6)
                    TextEditor(text: $prompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(minHeight: 86)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save Preferences") {
                    VoiceTranscriptionPreferences(language: language, prompt: prompt).save()
                    statusMessage = "Voice preferences saved."
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            let preferences = VoiceTranscriptionPreferences.load()
            language = preferences.language
            prompt = preferences.prompt
        }
    }

    private func saveKey() {
        do {
            try VoiceCredentialStore.save(apiKey: apiKey)
            apiKey = ""
            hasSavedKey = true
            statusMessage = "API key saved securely in your Mac Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try VoiceCredentialStore.remove()
            apiKey = ""
            hasSavedKey = false
            statusMessage = "API key removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
