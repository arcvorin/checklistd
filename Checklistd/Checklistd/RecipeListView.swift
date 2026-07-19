//
//  RecipeListView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct RecipeListView: View {
    let repository: Sync.RecipeRepositoryDetails
    let createExecution: (Program) -> Void
    
    var body: some View {
        List(Array(repository.files.enumerated()), id: \.offset) { _, program in
            Button {
                createExecution(program)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.title)
                        .font(.headline)
                    Text(program.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(repository.name)
        .checklistdInlineNavigationTitle()
    }
}
