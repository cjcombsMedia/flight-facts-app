import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FlightEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft = ""
    @State private var showKeyField = false

    var body: some View {
        @Bindable var s = settings

        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()

                Form {
                    Section {
                        Toggle("Notifications", isOn: $s.notificationsEnabled)
                        Toggle("Alert on points of interest", isOn: $s.notifyPOI)
                            .disabled(!s.notificationsEnabled)
                        Toggle("Alert on cabin advice", isOn: $s.notifyAdvice)
                            .disabled(!s.notificationsEnabled)
                        Toggle("Haptics", isOn: $s.hapticsEnabled)
                    } header: {
                        Text("Alerts")
                    } footer: {
                        Text("Descent, takeoff and border crossings always alert as time-sensitive. Everything else respects these switches.")
                    }

                    Section {
                        Picker("Chattiness", selection: $s.factDensity) {
                            ForEach(AppSettings.FactDensity.allCases) { d in
                                Text(d.label).tag(d)
                            }
                        }
                    } header: {
                        Text("Facts")
                    } footer: {
                        Text(settings.factDensity.blurb)
                    }

                    Section {
                        Picker("Map style", selection: $s.mapStyle) {
                            ForEach(AppSettings.MapStyleChoice.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        Toggle("3D terrain", isOn: $s.use3DTerrain)
                        Toggle("Imperial units", isOn: $s.useImperial)
                    } header: {
                        Text("Display")
                    } footer: {
                        Text("3D terrain downloads an elevation mesh on top of the map imagery. It's the main reason maps load slowly, and at cruise altitude the relief isn't visible anyway — leave it off unless you're low.")
                    }

                    Section {
                        Toggle("Lock Screen live facts", isOn: $s.liveActivityEnabled)
                    } header: {
                        Text("Lock Screen")
                    } footer: {
                        Text("Shows the current phase, altitude and latest fact on the Lock Screen and in the Dynamic Island, updating as you fly. Works in airplane mode — updates come from the app, not a server. Takes effect from the next flight.")
                    }

                    Section {
                        Toggle("Keep screen awake in flight", isOn: $s.keepScreenAwake)
                            .onChange(of: s.keepScreenAwake) { _, _ in
                                engine.refreshScreenAwakePreference()
                            }
                    } header: {
                        Text("Screen")
                    } footer: {
                        Text("Stops the display dimming while a flight is active, so you can glance at the map without unlocking. This costs real battery over a long flight — bring a power bank, or switch it off and rely on notifications.")
                    }

                    Section {
                        Toggle("Use network when available", isOn: $s.onlineEnrichment)
                    } header: {
                        Text("Online enrichment")
                    } footer: {
                        Text("Adds region and border detection plus extra map POIs when you have a signal. The bundled landmark and aviation history corpus works with no connection at all.")
                    }

                    Section {
                        Toggle("AI-generated facts", isOn: $s.aiFactsEnabled)
                            .disabled(!settings.hasAPIKey)

                        if settings.hasAPIKey && !showKeyField {
                            HStack {
                                Label("API key saved", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(Theme.mint)
                                Spacer()
                                Button("Replace") { showKeyField = true }
                                    .font(.footnote)
                            }
                            Button("Remove key", role: .destructive) {
                                settings.setAPIKey(nil)
                                s.aiFactsEnabled = false
                            }
                        } else {
                            SecureField("sk-ant-…", text: $apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Save key") {
                                settings.setAPIKey(apiKeyDraft)
                                apiKeyDraft = ""
                                showKeyField = false
                            }
                            .disabled(apiKeyDraft.count < 10)
                        }
                    } header: {
                        Text("Claude")
                    } footer: {
                        Text("Optional. Fills gaps over places the bundled corpus doesn't cover — open ocean, empty desert. The key is stored in the Keychain and called directly from this device, which is fine for a personal build. If you ever distribute this app, put the call behind a server you control instead.")
                    }

                    Section {
                        LabeledContent("Landmarks", value: "\(LandmarkStore.shared.all.count)")
                        LabeledContent("Location access", value: authLabel)
                        LabeledContent("Device", value: DeviceInfo.model)
                        LabeledContent("Version", value: version)
                    } header: {
                        Text("About")
                    } footer: {
                        Text("Flight logs export in the same TrackSession JSON format your RRCC app writes, so sessions move between the two.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(Theme.cyan)
                }
            }
            .tint(Theme.cyan)
        }
    }

    private var authLabel: String {
        switch engine.locationAuthorization {
        case .authorizedAlways:    return "Always"
        case .authorizedWhenInUse: return "When in use"
        case .denied:              return "Denied"
        case .restricted:          return "Restricted"
        default:                   return "Not set"
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
