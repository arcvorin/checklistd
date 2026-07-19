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
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.execution.program.title)
                        .font(.headline)
                    Text(file.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(repository.name)
        .checklistdInlineNavigationTitle()
    }
}
