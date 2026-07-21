//
//  ExecutionListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionListView: View {
    let repository: Sync.ExecutionRepositoryDetails
    let currentActor: GitCommitIdentity?
    var isRefreshing: Bool = false
    var refresh: () async -> Void = {}
    @State private var showsOnlyMine = true
    
    var body: some View {
        List {
            Section("In Progress") {
                if inProgressFiles.isEmpty {
                    Text(showsOnlyMine ? "No in-progress executions created by you" : "No in-progress executions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inProgressFiles, id: \.fileURL) { file in
                        NavigationLink(value: ExecutionRoute.file(file.fileURL)) {
                            ExecutionFileRow(file: file)
                        }
                    }
                }
            }
            
            Section("Completed") {
                if completedFiles.isEmpty {
                    Text(showsOnlyMine ? "No completed executions created by you" : "No completed executions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedFiles, id: \.fileURL) { file in
                        NavigationLink(value: ExecutionRoute.file(file.fileURL)) {
                            ExecutionFileRow(file: file)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            filterButton
                .padding(.leading, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle(repository.name)
        .checklistdInlineNavigationTitle()
        .refreshable {
            await refresh()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing executions")
                }
            }
        }
    }

    private var inProgressFiles: [Sync.ExecutionFileDetails] {
        filteredFiles.filter { !$0.execution.isCompleted }
    }

    private var completedFiles: [Sync.ExecutionFileDetails] {
        filteredFiles.filter(\.execution.isCompleted)
    }

    private var filteredFiles: [Sync.ExecutionFileDetails] {
        guard showsOnlyMine, let currentActor else {
            return repository.files
        }

        return repository.files.filter {
            $0.execution.createdByName == currentActor.name &&
                $0.execution.createdByEmail == currentActor.email
        }
    }

    private var filterButtonTitle: String {
        showsOnlyMine ? "Mine" : "All"
    }

    private var filterButtonSystemImage: String {
        showsOnlyMine ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    private var filterButton: some View {
        Button {
            showsOnlyMine.toggle()
        } label: {
            Label(filterButtonTitle, systemImage: filterButtonSystemImage)
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 3)
        .accessibilityLabel(showsOnlyMine ? "Show all executions" : "Show my executions")
        .disabled(currentActor == nil)
    }
}

private struct ExecutionFileRow: View {
    let file: Sync.ExecutionFileDetails
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !file.execution.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(file.execution.name)
                    .font(.headline)
                Text(file.execution.program.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(file.execution.program.title)
                    .font(.headline)
            }
            Text(file.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if file.execution.isCompleted {
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Text("Created by \(file.execution.createdByName) <\(file.execution.createdByEmail)>")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Created \(Self.timestampFormatter.string(from: file.execution.createdAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Updated \(Self.timestampFormatter.string(from: file.execution.updatedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
