//
//  RecipeRepositoryListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct RecipeRepositoryListView: View {
    let repositories: [Sync.RecipeRepositoryDetails]
    let createExecution: (Program, String) -> Void
    
    var body: some View {
        List(repositories, id: \.url) { repository in
            NavigationLink {
                RecipeListView(
                    repository: repository,
                    createExecution: { program in
                        createExecution(program, repository.url)
                    }
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                    Text("\(repository.files.count) recipes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
