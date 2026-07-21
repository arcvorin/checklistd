//
//  ExecutionRepositoryListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionRepositoryListView: View {
    let repositories: [Sync.ExecutionRepositoryDetails]
    var isRefreshing: Bool = false
    var refresh: () async -> Void = {}
    
    var body: some View {
        List(repositories, id: \.url) { repository in
            NavigationLink(value: ExecutionRoute.repository(repository.url)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                    Text("\(repository.files.count) executions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastUpdated = repository.files.map(\.execution.updatedAt).max() {
                        Text("Last updated \(Self.timestampFormatter.string(from: lastUpdated))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
