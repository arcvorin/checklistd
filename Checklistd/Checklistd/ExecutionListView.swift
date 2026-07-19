//
//  ExecutionListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionListView: View {
    let repository: Sync.ExecutionRepositoryDetails
    
    var body: some View {
        List(repository.files, id: \.fileURL) { file in
            NavigationLink(value: ExecutionRoute.file(file.fileURL)) {
                ExecutionFileRow(file: file)
            }
        }
        .navigationTitle(repository.name)
        .checklistdInlineNavigationTitle()
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
