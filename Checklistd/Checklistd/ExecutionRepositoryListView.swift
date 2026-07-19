//
//  ExecutionRepositoryListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionRepositoryListView: View {
    let repositories: [Sync.ExecutionRepositoryDetails]
    
    var body: some View {
        List(repositories, id: \.url) { repository in
            NavigationLink {
                ExecutionListView(repository: repository)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                    Text("\(repository.files.count) executions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
