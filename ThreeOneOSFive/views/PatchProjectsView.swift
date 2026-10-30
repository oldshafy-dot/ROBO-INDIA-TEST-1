import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "shafay") ?? .data
    static let legacyPackageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, legacyPackageType, .data]
    static let copiesSelectedDocument = true
}

private enum WallpaperPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var store: PatchProjectStore
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true

    @State private var onlineGame = OnlinePatchGame.freeFireNormal
    @State private var onlinePatch: PublicPatchResponse?
    @State private var onlinePatchMessage: String?
    @State private var isRefreshingOnlinePatch = false
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var showWallpaperImporter = false
    @State private var showCleaner = false
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedPatchIDs = Set<UUID>()
    @State private var enabledPatchIDs = Set<UUID>()
    @State private var workingPatchIDs = Set<UUID>()
    @State private var showPatchActionAlert = false
    @State private var patchActionAlertTitle = "Patch"
    @State private var patchActionAlertMessage = ""
    @State private var wallpaperPackages: [WallpaperStagedPackage] = []
    @State private var wallpaperImportFeedback: WallpaperImportFeedback?
    @State private var wallpaperPendingDeletion: WallpaperStagedPackage?
    @State private var isImportingWallpapers = false
    @State private var showSimulatedWallpaperDetail = false
    @State private var simulatedWallpaperDetailGate = OneShotPresentationGate()

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private var filteredItems: [PatchLibraryItem] {
        store.items
    }

    private var filteredWallpaperPackages: [WallpaperStagedPackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return wallpaperPackages }

        return wallpaperPackages.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var hasLocalContent: Bool {
        !store.items.isEmpty || !wallpaperPackages.isEmpty
    }

    private var hasSearchResults: Bool {
        !filteredItems.isEmpty || !filteredWallpaperPackages.isEmpty
    }

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs

        #if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains(
                "--simulate-patch-editor"
            )
        )
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                patchList
            }
            .background(Color.clear)
            .navigationTitle("Functions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(role: .destructive) {
                            let itemsToDelete = store.items.filter {
                                selectedPatchIDs.contains($0.id)
                            }

                            for item in itemsToDelete {
                                store.delete(item)
                            }

                            selectedPatchIDs.removeAll()
                            isSelecting = false
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .disabled(selectedPatchIDs.isEmpty || store.isBusy)
                        .accessibilityLabel("Delete selected patches")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label(
                                "Import Shafay",
                                systemImage: "square.and.arrow.down"
                            )
                        }

                        Button {
                            isSelecting.toggle()

                            if !isSelecting {
                                selectedPatchIDs.removeAll()
                            }
                        } label: {
                            Label(
                                isSelecting ? "Cancel Selection" : "Select",
                                systemImage: "checkmark.circle"
                            )
                        }

                        if !store.items.isEmpty {
                            Button {
                                isSelecting = true
                                selectedPatchIDs = Set(store.items.map(\.id))
                            } label: {
                                Label(
                                    "Select All",
                                    systemImage: "checkmark.circle.fill"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .disabled(store.isBusy)
                }
            }
            .alert(patchActionAlertTitle, isPresented: $showPatchActionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(patchActionAlertMessage)
            }
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showImporter = false

                        if case .success(let urls) = result,
                           let url = urls.first {
                            store.importPackage(at: url)
                        }
                    },
                    onCancel: {
                        showImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(isPresented: $showCleaner) {
                CleanerView()
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .sheet(isPresented: $showWallpaperImporter) {
                FileDocumentPicker(
                    allowedContentTypes: WallpaperPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: true,
                    onSelection: { result in
                        showWallpaperImporter = false

                        if case .success(let urls) = result,
                           !urls.isEmpty {
                            importWallpaperPackages(urls)
                        }
                    },
                    onCancel: {
                        showWallpaperImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert(item: $wallpaperImportFeedback) { feedback in
                Alert(
                    title: Text(language.text(feedback.titleKey)),
                    message: Text(feedback.message),
                    dismissButton: .default(
                        Text(language.text("common.ok"))
                    )
                )
            }
            .alert(item: $wallpaperPendingDeletion) { package in
                Alert(
                    title: Text(language.text("wallpaper.delete_title")),
                    message: Text(
                        language.text(
                            "wallpaper.delete_message",
                            package.displayName
                        )
                    ),
                    primaryButton: .destructive(
                        Text(language.text("common.delete"))
                    ) {
                        deleteWallpaperPackage(package)
                    },
                    secondaryButton: .cancel(
                        Text(language.text("common.cancel"))
                    )
                )
            }
            .onAppear {
                Task {
                    await refreshOnlinePatch()
                }

                reloadWallpaperPackages()
                consumeExternalImport()
            }
        }
    }

    private var patchList: some View {
        List {
            if let onlinePatch {
                onlinePatchSection(onlinePatch)
            }

            if let onlinePatchMessage {
                Section {
                    Text(onlinePatchMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Color.blue.opacity(0.75),
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import 31-05")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(
                            language.text(
                                "patch.library_count",
                                Int64(store.items.count)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 38, height: 38)
                            .background(
                                Color.blue.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy)
                }
                .padding(.vertical, 5)
                .listRowBackground(Color.clear)
            }

            if hasLocalContent {
                Section {
                    if !filteredItems.isEmpty {
                        ForEach(filteredItems) { item in
                            patchRow(item)
                        }
                    }

                    if !filteredWallpaperPackages.isEmpty {
                        ForEach(filteredWallpaperPackages) { package in
                            wallpaperRow(package)
                        }
                    }
                } header: {
                    HStack {
                        Text("Functions")

                        Spacer()

                        if isSelecting {
                            Button("Cancel") {
                                isSelecting = false
                                selectedPatchIDs.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Patches",
                    systemImage: "square.stack.3d.up",
                    description: Text(
                        "Import a patch package to get started."
                    )
                )
                .listRowBackground(Color.clear)
            }

            if !hasSearchResults && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search functions")
        .overlay {
            if store.isBusy || isImportingWallpapers {
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func patchRow(_ item: PatchLibraryItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(
                    systemName: selectedPatchIDs.contains(item.id)
                    ? "checkmark.circle.fill"
                    : "circle"
                )
                .font(.system(size: 21))
                .foregroundStyle(
                    selectedPatchIDs.contains(item.id) ? .blue : .secondary
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.summary.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(item.summary.versionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.summary.isApplied {
                    Text("Applied")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 6)

            patchToggleButton(item)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedPatchIDs.contains(item.id) {
                    selectedPatchIDs.remove(item.id)
                } else {
                    selectedPatchIDs.insert(item.id)
                }
            } else {
                openPatch(item)
            }
        }
        .contextMenu {
            Button {
                openPatch(item)
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                exportPatch(item)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                store.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func patchToggleButton(_ item: PatchLibraryItem) -> some View {
        Toggle(
            item.summary.displayName,
            isOn: Binding(
                get: {
                    enabledPatchIDs.contains(item.id)
                },
                set: { isEnabled in
                    if isEnabled {
                        enabledPatchIDs.insert(item.id)
                        applyPatch(item)
                    } else {
                        enabledPatchIDs.remove(item.id)
                        restorePatch(item)
                    }
                }
            )
        )
        .labelsHidden()
        .disabled(workingPatchIDs.contains(item.id) || store.isBusy)
        .tint(.blue)
    }

    private func openPatch(_ item: PatchLibraryItem) {
        guard !store.isBusy else { return }

        store.select(item)
    }

    private func exportPatch(_ item: PatchLibraryItem) {
        guard !store.isBusy else { return }

        store.export(item)
    }

    private func applyPatch(_ item: PatchLibraryItem) {
        guard !workingPatchIDs.contains(item.id) else { return }
        workingPatchIDs.insert(item.id)

        Task {
            do {
                try await store.apply(item)
                workingPatchIDs.remove(item.id)
            } catch {
                workingPatchIDs.remove(item.id)
                enabledPatchIDs.remove(item.id)
                patchActionAlertTitle = "Patch Failed"
                patchActionAlertMessage = error.localizedDescription
                showPatchActionAlert = true
            }
        }
    }

    private func restorePatch(_ item: PatchLibraryItem) {
        guard !workingPatchIDs.contains(item.id) else { return }
        workingPatchIDs.insert(item.id)

        Task {
            do {
                try await store.restore(item)
                workingPatchIDs.remove(item.id)
            } catch {
                workingPatchIDs.remove(item.id)
                enabledPatchIDs.insert(item.id)
                patchActionAlertTitle = "Restore Failed"
                patchActionAlertMessage = error.localizedDescription
                showPatchActionAlert = true
            }
        }
    }
