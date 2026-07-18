//
//  Login.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-17.
//

import SwiftUI
import OctoKit
struct LoginView: View {
    @State var newPAT: String = ""
    @Binding var sync: Sync
    @State var repos: [OctoKit.Repository] = []
    @State var syncedRapos: [Sync.SyncRepo] = []
    @State var isAuthenticated = false
    var body: some View {
        Text("Authenticated: \(isAuthenticated)")
        HStack {
            TextField("PAT", text: $newPAT)
                .onSubmit {
                    _ = sync.setPAT(newPAT)
                    isAuthenticated = !newPAT.isEmpty
                    newPAT = ""
                }
                .padding()
                .onAppear {
                    if (sync.isAuthenticated()) {
                        isAuthenticated = true
                        Task {
                            guard let repos = await sync.listRepos() else {
                                return
                            }
                            self.repos = repos
                            self.syncedRapos = sync.repos
                        }
                    } else {
                        isAuthenticated = false
                    }
                }
            Button(isAuthenticated ? "Update" : "Submit") {
                _ = sync.setPAT(newPAT)
                isAuthenticated = !newPAT.isEmpty
                newPAT = ""

                Task {
                    guard let repos = await sync.listRepos() else {
                        self.syncedRapos = []
                        return self.repos = []
                    }
                    self.repos = repos
                    self.syncedRapos = sync.repos
                }
            }.padding()
        }
        VStack {
            List(repos, id: \.id) { aRepo in
                HStack {
                    Text(aRepo.name ?? "No Name")
                    Spacer()
                    Text(syncedRapos.filter { syncRepo in
                        syncRepo.url == aRepo.cloneURL
                    }.map { $0.kind.rawValue }.joined(separator: ", "))
                }.onTapGesture {
                    let kinds = syncedRapos.filter { syncRepo in
                        syncRepo.url == aRepo.cloneURL
                    }.map { $0.kind }
                    if kinds.contains(.recipe) && kinds.contains(.execution) {
                        sync.untrackRepo(repository: aRepo)
                        self.syncedRapos = sync.repos
                        return
                    }
                    if kinds.isEmpty {
                        sync.trackRepo(repository: aRepo, as: .recipe)
                        self.syncedRapos = sync.repos
                        return
                    }
                    if kinds.contains(.recipe) {
                        sync.untrackRepo(repository: aRepo)
                        sync.trackRepo(repository: aRepo, as: .execution)
                        self.syncedRapos = sync.repos
                        return
                    }
                    if kinds.contains(.execution) {
                        sync.untrackRepo(repository: aRepo)
                        sync.trackRepo(repository: aRepo, as: .recipe)
                        sync.trackRepo(repository: aRepo, as: .execution)
                        self.syncedRapos = sync.repos
                        return
                    }
                }
            }
        }
    }
    
}
