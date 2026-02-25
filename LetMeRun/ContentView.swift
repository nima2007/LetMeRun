import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var droppedItem: DroppedItem? = nil
    @State private var isTargeted = false
    @State private var isScanning = false

    struct DroppedItem {
        let name: String
        let path: String
        let icon: NSImage
        var result: QuarantineResult
    }

    var body: some View {
        VStack(spacing: 0) {
            if isScanning {
                scanningView
            } else if let item = droppedItem {
                itemDetailView(item: item)
            } else {
                dropZoneView
            }
        }
        .frame(width: 440, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning files...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop a file, folder, or application here")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
                .padding(16)
        )
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }

    // MARK: - Item Detail View

    private func itemDetailView(item: DroppedItem) -> some View {
        VStack(spacing: 16) {
            Spacer()

            // Item icon
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            // Item name & path
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 380)

                Text(item.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 380)
            }

            // Status Badge
            statusBadge(for: item.result)

            // Action Buttons
            HStack(spacing: 10) {
                if item.result.status == .quarantined || item.result.status == .partial {
                    Button(action: {
                        removeQuarantine()
                    }) {
                        Text(item.result.status == .partial ? "Remove All Quarantine Flags" : "LetMeRun")
                    }
                    .controlSize(.large)
                }

                Button(item.result.status == .clean ? "Done" : "Cancel") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        droppedItem = nil
                    }
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction) // Make it the default return action when clean
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .animation(.easeInOut(duration: 0.2), value: item.result)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(for result: QuarantineResult) -> some View {
        VStack(spacing: 6) {
            switch result.status {
            case .quarantined:
                Label("Fully Quarantined", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)

            case .partial:
                Label("Partially Quarantined", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)

            case .clean:
                Label("Not Quarantined", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)

            case .error(let message):
                Label("Error", systemImage: "xmark.doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            // Detail Text
            if result.totalFiles > 0 {
                let quarantinedText = result.quarantinedFiles == 1 ? "1 file" : "\(result.quarantinedFiles) files"
                let totalText = result.totalFiles == 1 ? "1 file" : "\(result.totalFiles) total"

                Text("\(quarantinedText) quarantined out of \(totalText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }

    // MARK: - Logic

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let path = url.path
                let name = url.lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 512, height: 512)

                // Start scanning
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isScanning = true
                    }
                }

                // Check quarantine in background
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = QuarantineRemover.checkQuarantine(at: path)

                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isScanning = false
                            self.droppedItem = DroppedItem(
                                name: name,
                                path: path,
                                icon: icon,
                                result: result
                            )
                        }
                    }
                }
            }
        }
    }

    private func removeQuarantine() {
        guard let item = droppedItem else { return }

        withAnimation(.easeInOut) {
            isScanning = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let freshResult = QuarantineRemover.removeQuarantine(at: item.path)

            DispatchQueue.main.async {
                withAnimation(.easeInOut) {
                    self.isScanning = false
                    self.droppedItem?.result = freshResult
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
