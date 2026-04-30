import AppAttestVerifyKit
import SwiftUI
import UniformTypeIdentifiers

struct AppAttestVerifyDemoView: View {
    @StateObject private var viewModel = AppAttestVerifyDemoViewModel()
    @State private var importTarget: AppAttestVerifyImportTarget?
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DebugPanel(statusText: viewModel.statusText, debugText: viewModel.debugText)

                TabView {
                    AttestationTab(viewModel: viewModel, presentImporter: presentImporter)
                        .tabItem {
                            Label("Attestation", systemImage: "checkmark.seal")
                        }

                    AssertionTab(viewModel: viewModel, presentImporter: presentImporter)
                        .tabItem {
                            Label("Assertion", systemImage: "signature")
                        }
                }
            }
            .navigationTitle("App Attest Verify")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadStoredState()
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.data, .json, .item],
                allowsMultipleSelection: false
            ) { result in
                // `fileImporter` flips `isPresented` back to false before this
                // closure runs, so keep the selected import role in a separate
                // state value until the file has been handed to the view model.
                let target = importTarget
                defer {
                    importTarget = nil
                }
                viewModel.handleFileImport(result, target: target)
            }
        }
    }

    private func presentImporter(_ target: AppAttestVerifyImportTarget) {
        importTarget = target
        isFileImporterPresented = true
    }
}

private struct DebugPanel: View {
    let statusText: String
    let debugText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                    if !debugText.isEmpty {
                        Divider()
                        Text(debugText)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 188)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct AttestationTab: View {
    @ObservedObject var viewModel: AppAttestVerifyDemoViewModel
    let presentImporter: (AppAttestVerifyImportTarget) -> Void

    var body: some View {
        Form {
            Section("Context") {
                TextField("Team ID", text: $viewModel.teamId)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Bundle ID", text: $viewModel.bundleId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Environment", selection: $viewModel.environment) {
                    ForEach(AppAttestEnvironment.allCases, id: \.self) { environment in
                        Text(environment.rawValue.capitalized).tag(environment)
                    }
                }
                TextField("Raw challenge", text: $viewModel.rawChallenge, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)
            }

            Section("Artifacts") {
                LabeledContent("Attestation CBOR", value: viewModel.attestationFileName)
                Button {
                    presentImporter(.attestationObject)
                } label: {
                    Label("Choose Attestation CBOR", systemImage: "doc.badge.plus")
                }

                LabeledContent("Root Anchor", value: viewModel.rootAnchorFileName)
                Button {
                    presentImporter(.rootAnchor)
                } label: {
                    Label("Choose Root Anchor", systemImage: "doc.text.magnifyingglass")
                }

                TextField("Verification time (Unix seconds)", text: $viewModel.verificationTimeUnixSeconds)
                    .keyboardType(.numberPad)
            }

            Section {
                Toggle("Input prefilter", isOn: $viewModel.inputCheckEnabled)
                Button {
                    viewModel.verifyAttestation()
                } label: {
                    Label("Verify Attestation", systemImage: "checkmark.shield")
                }
                .disabled(viewModel.isWorking)
            }
        }
    }
}

private struct AssertionTab: View {
    @ObservedObject var viewModel: AppAttestVerifyDemoViewModel
    let presentImporter: (AppAttestVerifyImportTarget) -> Void

    var body: some View {
        Form {
            Section("Saved State") {
                Text(viewModel.storedStateSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Button(role: .destructive) {
                    viewModel.clearStoredState()
                } label: {
                    Label("Clear Stored State", systemImage: "trash")
                }
                .disabled(viewModel.isWorking || viewModel.storedState == nil)
            }

            Section("Artifacts") {
                LabeledContent("Assertion CBOR", value: viewModel.assertionFileName)
                Button {
                    presentImporter(.assertionObject)
                } label: {
                    Label("Choose Assertion CBOR", systemImage: "doc.badge.plus")
                }

                LabeledContent("Client Data File", value: viewModel.clientDataFileName)
                Button {
                    presentImporter(.clientData)
                } label: {
                    Label("Choose Client Data", systemImage: "doc.text")
                }

                TextField("Raw clientData", text: $viewModel.clientDataText, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...8)
            }

            Section {
                Picker("Counter policy", selection: $viewModel.counterPolicyMode) {
                    ForEach(AppAttestVerifyCounterPolicyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Button {
                    viewModel.verifyAssertion()
                } label: {
                    Label("Verify Assertion", systemImage: "signature")
                }
                .disabled(viewModel.isWorking || viewModel.storedState == nil)
            }
        }
    }
}
