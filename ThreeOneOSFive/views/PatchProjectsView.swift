// File: ThreeOneOSFive/views/PatchProjectsView.swift
// Replace the existing `var body: some View` property with this complete property.
// Keep the rest of the file unchanged.

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

            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains(
                "--simulate-wallpaper-detail"
            ),
            !wallpaperPackages.isEmpty,
            simulatedWallpaperDetailGate.claim() {
                DispatchQueue.main.async {
                    showSimulatedWallpaperDetail = true
                }
            }
            #endif
        }
        .navigationDestination(
            isPresented: $showSimulatedWallpaperDetail
        ) {
            if let package = wallpaperPackages.first {
                InstalledWallpaperPackageDetailView(
                    package: package,
                    onApplied: reloadWallpaperPackages
                )
            }
        }
        .onChange(of: draftCoordinator.importRequest?.id) { _ in
            consumeExternalImport()
        }
        .onChange(of: onlineGame) { _ in
            Task {
                await refreshOnlinePatch()
            }
        }
    }
}

private var patchList: some View {
    List {
        onlinePatchSection

        if store.items.isEmpty && store.isBusy {
            loadingState
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if store.items.isEmpty {
            emptyState
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            localPatchSection
        }
    }
    .scrollContentBackground(.hidden)
    .background(Color.clear)
    .listStyle(.insetGrouped)
    .environment(\.defaultMinListRowHeight, 64)
}

private var onlinePatchSection: some View {
    Section {
        Picker("Select Game", selection: $onlineGame) {
            ForEach(OnlinePatchGame.allCases) { game in
                Text(game.title).tag(game)
            }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)

        onlinePatchCard
            .listRowBackground(Color.clear)
    } header: {
        Text("Online Patches")
            .foregroundStyle(.white)
    }
}

private var onlinePatchCard: some View {
    HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
            Text(onlinePatchTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text(onlinePatchDescription)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 4)

        Button {
            Task {
                await refreshOnlinePatch()
            }
        } label: {
            if isRefreshingOnlinePatch {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.20, green: 0.68, blue: 1.0))
        .disabled(isRefreshingOnlinePatch)
        .accessibilityLabel("Refresh online patches")
    }
    .padding(10)
    .background(
        Color.white.opacity(0.055),
        in: RoundedRectangle(cornerRadius: 12)
    )
}

private var onlinePatchTitle: String {
    if let version = onlinePatch?.version {
        return ".\(version)"
    }

    return "Online Patches"
}

private var onlinePatchDescription: String {
    onlinePatch?.notes
        ?? onlinePatchMessage
        ?? "There are no patches yet. Soon, patches will be updated. Please check back later."
}

private var localPatchSection: some View {
    Section {
        ForEach(store.items) { item in
            localPatchRow(item)
        }
    } header: {
        Text("Patches")
            .foregroundStyle(.white)
    }
}

private func localPatchRow(_ item: PatchLibraryItem) -> some View {
    HStack(spacing: 12) {
        if isSelecting {
            Button {
                togglePatchSelection(item.id)
            } label: {
                Image(
                    systemName: selectedPatchIDs.contains(item.id)
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }

        functionPatchRow(item)
            .frame(maxWidth: .infinity, alignment: .leading)

        if item.isLocked {
            Button {
                store.requestUnlock(for: item)
            } label: {
                Text("Unlock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color.gray.opacity(0.35),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        } else {
            patchToggleButton(item)
        }
    }
    .padding(.vertical, 5)
    .listRowBackground(
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
    )
    .listRowSeparatorTint(Color.gray.opacity(0.45))
}

private func togglePatchSelection(_ id: UUID) {
    if selectedPatchIDs.contains(id) {
        selectedPatchIDs.remove(id)
    } else {
        selectedPatchIDs.insert(id)
    }
}

private func patchToggleButton(_ item: PatchLibraryItem) -> some View {
    let isEnabled = DevicePatchService.latestReceipt(projectID: item.id) != nil
    let isWorking = workingPatchIDs.contains(item.id)

    return Button {
        setPatch(item, enabled: !isEnabled)
    } label: {
        HStack(spacing: 6) {
            Text(isWorking ? "…" : (isEnabled ? "ON" : "OFF"))
                .font(.system(size: 12, weight: .bold))

            if isWorking {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.7)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 66, height: 34)
        .background(
            isEnabled
                ? Color.green.opacity(0.78)
                : Color.gray.opacity(0.48),
            in: Capsule()
        )
    }
    .buttonStyle(.plain)
    .disabled(isWorking || store.isBusy)
    .accessibilityLabel(
        isEnabled
            ? "Turn patch off and restore original"
            : "Turn patch on and apply"
    )
}
