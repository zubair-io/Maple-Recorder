#if !os(watchOS)
import SwiftUI

struct PromptPickerView: View {
    let prompts: [CustomPrompt]
    let provider: LLMProvider
    var onSelect: (CustomPrompt, String?) -> Void
    @State private var additionalContext: String = ""
    @State private var selectedPrompt: CustomPrompt?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    providerBadge
                }

                Section("Select a Prompt") {
                    ForEach(prompts) { prompt in
                        Button {
                            selectedPrompt = prompt
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prompt.name)
                                    .font(.headline)
                                    .foregroundStyle(MapleTheme.textPrimary)
                                Text(prompt.systemPrompt)
                                    .font(.caption)
                                    .foregroundStyle(MapleTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if selectedPrompt != nil {
                    Section {
                        TextField("Additional context (optional)", text: $additionalContext, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("Additional Context")
                    } footer: {
                        Text("Optionally provide extra context to guide the prompt.")
                    }

                    Section {
                        Button {
                            if let prompt = selectedPrompt {
                                let context = additionalContext.isEmpty ? nil : additionalContext
                                onSelect(prompt, context)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Run Prompt", systemImage: "play.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Run Prompt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var providerBadge: some View {
        let isCloud = provider == .claude || provider == .openai
        HStack(spacing: 8) {
            Image(systemName: isCloud ? "cloud.fill" : "iphone")
                .foregroundStyle(isCloud ? MapleTheme.info : MapleTheme.success)
            VStack(alignment: .leading) {
                Text(isCloud ? "Cloud" : "On-Device")
                    .font(.subheadline.weight(.semibold))
                Text(providerDisplayName)
                    .font(.caption)
                    .foregroundStyle(MapleTheme.textSecondary)
            }
        }
    }

    private var providerDisplayName: String {
        switch provider {
        case .appleFoundationModels: "Apple Foundation Models"
        case .claude: "Claude"
        case .openai: "OpenAI"
        case .none: "Off"
        }
    }
}
#endif
