//
//  ExecutionListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionListView: View {
    let repository: Sync.ExecutionRepositoryDetails
    var isRefreshing: Bool = false
    var refresh: () async -> Void = {}
    
    var body: some View {
        List {
            Section("In Progress") {
                if inProgressFiles.isEmpty {
                    Text("No in-progress executions")
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
                    Text("No completed executions")
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
        repository.files.filter { !$0.execution.isCompleted }
    }

    private var completedFiles: [Sync.ExecutionFileDetails] {
        repository.files.filter(\.execution.isCompleted)
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
