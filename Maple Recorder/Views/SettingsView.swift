#if !os(watchOS)
import SwiftUI

struct SettingsView: View {
    @Bindable var settingsManager: SettingsManager
    @Bindable var promptStore: PromptStore
    @State private var claudeKey: String = ""
    @State private var openAIKey: String = ""
    @State private var showingAddPrompt = false
    @State private var newPromptName = ""
    @State private var newPromptBody = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // LLM Provider
                Section("LLM Provider") {
                    Picker("Provider", selection: $settingsManager.preferredProvider) {
                        Text("Apple On-Device").tag(LLMProvider.appleFoundationModels)
                        Text("Claude (Cloud)").tag(LLMProvider.claude)
                        Text("OpenAI (Cloud)").tag(LLMProvider.openai)
                        Text("Off").tag(LLMProvider.none)
                    }

                    if settingsManager.preferredProvider == .appleFoundationModels {
                        Label("Runs entirely on-device — audio and text never leave your device.", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundStyle(MapleTheme.success)
                    }
                }

                // API Keys
                if settingsManager.preferredProvider == .claude || settingsManager.preferredProvider == .openai {
                    Section {
                        if settingsManager.preferredProvider == .claude {
                            SecureField("Claude API Key", text: $claudeKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .onChange(of: claudeKey) { _, newValue in
                                    settingsManager.claudeAPIKey = newValue
                                }
                        }
                        if settingsManager.preferredProvider == .openai {
                            SecureField("OpenAI API Key", text: $openAIKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .onChange(of: openAIKey) { _, newValue in
                                    settingsManager.openAIAPIKey = newValue
                                }
                        }
                    } header: {
                        Text("API Keys")
                    } footer: {
                        Text("Keys are stored securely in your device's Keychain and never synced to iCloud.")
                    }
                }

                // Custom Prompts
                Section {
                    ForEach(promptStore.prompts) { prompt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.name)
                                .font(.headline)
                            Text(prompt.systemPrompt)
                                .font(.caption)
                                .foregroundStyle(MapleTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .onDelete { indices in
                        for index in indices {
                            try? promptStore.delete(promptStore.prompts[index])
                        }
                    }

                    Button {
                        showingAddPrompt = true
                    } label: {
                        Label("Add Prompt", systemImage: "plus")
                    }
                } header: {
                    Text("Custom Prompts")
                } footer: {
                    Text("Prompts sync across your devices via iCloud.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                claudeKey = settingsManager.claudeAPIKey
                openAIKey = settingsManager.openAIAPIKey
            }
            .alert("New Prompt", isPresented: $showingAddPrompt) {
                TextField("Prompt name", text: $newPromptName)
                TextField("System prompt", text: $newPromptBody)
                Button("Cancel", role: .cancel) {
                    newPromptName = ""
                    newPromptBody = ""
                }
                Button("Add") {
                    let prompt = CustomPrompt(
                        id: UUID(),
                        name: newPromptName,
                        systemPrompt: newPromptBody,
                        createdAt: Date()
                    )
                    try? promptStore.add(prompt)
                    newPromptName = ""
                    newPromptBody = ""
                }
            } message: {
                Text("Enter a name and system prompt for your custom prompt.")
            }
        }
    }
}
#endif
