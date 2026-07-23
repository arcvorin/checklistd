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
    var isRefreshing: Bool = false
    var refresh: () async -> Void = {}
    var navigateTo: (String) -> Void = { _ in }

    var body: some View {
        List(repositories, id: \.url) { repository in
            NavigationLink(value: repository.url) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                    Text("\(repository.files.count) recipes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .onAppear {
            if (self.repositories.count == 1) {
                self.navigateTo(self.repositories[0].url)
            }
        }
        .onChange(of: self.repositories.map(\.url)) {
            if self.repositories.count == 1 {
                navigateTo(self.repositories[0].url)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing recipes")
                }
            }
        }
    }
}
