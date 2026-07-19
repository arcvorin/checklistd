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
    @State var gitCommitName: String = ""
    @State var gitCommitEmail: String = ""
    @Binding var sync: Sync
    @State var repos: [OctoKit.Repository] = []
    @State var pairs: [Sync.RecipeExecutionPair] = []
    @State var recipeRepositories: [Sync.RecipeRepositoryDetails] = []
    @State var executionRepositories: [Sync.ExecutionRepositoryDetails] = []
    @State var isAuthenticated = false
    @State private var selectedTab: AppTab = .setup
    @State private var executionPath: [URL] = []
    @State private var setupStateVersion = 0
    @State private var isContinuing = false
    @State private var isShowingExecutionPicker: Bool = false
    @State private var selectedRecipeRepo: OctoKit.Repository? = nil
    @State private var selectedExecutionRepoURL: String = ""
    
    private enum AppTab {
        case setup
        case recipes
        case executions
    }

    var body: some View {
        Group {
            if isSetupComplete {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        setupView
                            .navigationTitle("Setup")
                    }
                    .tabItem {
                        Label("Setup", systemImage: "gearshape")
                    }
                    .tag(AppTab.setup)
                    
                    NavigationStack {
                        RecipeRepositoryListView(
                            repositories: recipeRepositories,
                            createExecution: createExecution
                        )
                        .navigationTitle("Recipe Repos")
                    }
                    .tabItem {
                        Label("Recipes", systemImage: "list.bullet.rectangle")
                    }
                    .tag(AppTab.recipes)
                    
                    NavigationStack(path: $executionPath) {
                        ExecutionRepositoryListView(repositories: executionRepositories)
                            .navigationTitle("Execution Repos")
                            .navigationDestination(for: URL.self) { fileURL in
                                if let file = executionFile(for: fileURL) {
                                    ExecutionDetailView(file: file, sync: sync)
                                } else {
                                    Text("Execution not found")
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                    .tabItem {
                        Label("Executions", systemImage: "checklist")
                    }
                    .tag(AppTab.executions)
                }
            } else {
                NavigationStack {
                    setupView
                        .navigationTitle("Setup")
                }
            }
        }
        .onAppear {
            loadAuthenticatedState()
        }
        .sheet(isPresented: $isShowingExecutionPicker) {
            executionPickerSheet
        }
    }
    
    private var setupView: some View {
        VStack {
            Text(isSetupComplete ? "Setup complete" : "Setup incomplete")
            HStack {
                TextField("PAT", text: $newPAT)
                    .onSubmit {
                        saveSetup()
                    }
                    .padding()
                Button(isAuthenticated ? "Update" : "Submit") {
                    saveSetup()
                }
                .padding()
            }
            TextField("Git commit name", text: $gitCommitName)
                .padding(.horizontal)
                .textFieldStyle(.roundedBorder)
            TextField("Git commit email", text: $gitCommitEmail)
                .padding(.horizontal)
                .textFieldStyle(.roundedBorder)
            List(repos, id: \.id) { repo in
                repoPairingRow(repo)
            }
            Spacer()
            Button(syncButtonTitle) {
                if isSetupComplete {
                    continueToRecipes()
                } else {
                    saveSetup()
                }
            }
            .disabled(isContinuing)
            .padding()
        }
    }
    
    private func repoPairingRow(_ repo: OctoKit.Repository) -> some View {
        HStack {
            Text(repo.name ?? "No Name")
            Spacer()
            if let pair = pairs.first(where: { $0.recipeURL == repo.cloneURL }) {
                Text("-> \(pair.executionName)")
            } else {
                Text("Tap to pair")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRecipeRepo = repo
            isShowingExecutionPicker = true
        }
    }
    
    @ViewBuilder
    private var executionPickerSheet: some View {
        if let recipeRepo = selectedRecipeRepo {
            VStack(spacing: 20) {
                Picker("Execution Repository", selection: $selectedExecutionRepoURL) {
                    ForEach(repos, id: \.id) { repo in
                        Text(repo.name ?? "No Name").tag(repo.cloneURL ?? "")
                    }
                }
                .checklistdExecutionPickerStyle()
                .labelsHidden()
                HStack {
                    Button("Save") {
                        guard let executionRepo = repos.first(where: { $0.cloneURL == selectedExecutionRepoURL }) else { return }
                        sync.setPair(recipe: recipeRepo, execution: executionRepo)
                        pairs = sync.listPairs()
                        refreshRecipeRepositories()
                        refreshExecutionRepositories()
                        isShowingExecutionPicker = false
                        selectedRecipeRepo = nil
                    }
                    Spacer()
                    Button("Remove Pair") {
                        sync.removePair(for: recipeRepo)
                        pairs = sync.listPairs()
                        refreshRecipeRepositories()
                        refreshExecutionRepositories()
                        isShowingExecutionPicker = false
                        selectedRecipeRepo = nil
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .onAppear {
                if let existingPair = pairs.first(where: { $0.recipeURL == recipeRepo.cloneURL }) {
                    selectedExecutionRepoURL = existingPair.executionURL
                } else {
                    selectedExecutionRepoURL = recipeRepo.cloneURL ?? ""
                }
            }
        } else {
            EmptyView()
        }
    }
    
    private func loadAuthenticatedState() {
        gitCommitName = sync.gitCommitName()
        gitCommitEmail = sync.gitCommitEmail()
        
        if sync.isAuthenticated() {
            isAuthenticated = true
            Task {
                guard let repos = await sync.listRepos() else {
                    return
                }
                self.repos = repos
                self.pairs = sync.listPairs()
                refreshRecipeRepositories()
                refreshExecutionRepositories()
            }
        } else {
            isAuthenticated = false
        }
    }
    
    private func saveSetup() {
        sync.setGitCommitIdentity(name: gitCommitName, email: gitCommitEmail)
        
        if !newPAT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = sync.setPAT(newPAT)
        }
        
        isAuthenticated = sync.isAuthenticated()
        newPAT = ""
        setupStateVersion += 1
        
        Task {
            guard let repos = await sync.listRepos() else {
                self.pairs = []
                self.repos = []
                return
            }
            self.repos = repos
            self.pairs = sync.listPairs()
            refreshRecipeRepositories()
            refreshExecutionRepositories()
        }
    }
    
    private func continueToRecipes() {
        isContinuing = true
        Task {
            await sync.pullRepos()
            let repositories = refreshRecipeRepositories()
            let executionRepositories = refreshExecutionRepositories()
            await MainActor.run {
                recipeRepositories = repositories
                self.executionRepositories = executionRepositories
                selectedTab = .recipes
                isContinuing = false
            }
        }
    }
    
    private var syncButtonTitle: String {
        if isContinuing {
            return "Loading..."
        }
        
        return isSetupComplete ? "Sync" : "Complete Setup"
    }
    
    private var isSetupComplete: Bool {
        _ = setupStateVersion
        return sync.isAuthenticated() && sync.gitCommitIdentity() != nil
    }
    
    @discardableResult
    private func refreshRecipeRepositories() -> [Sync.RecipeRepositoryDetails] {
        let repositories = sync.listRecipes()
        recipeRepositories = repositories
        return repositories
    }
    
    @discardableResult
    private func refreshExecutionRepositories() -> [Sync.ExecutionRepositoryDetails] {
        let repositories = sync.listExecutions()
        executionRepositories = repositories
        return repositories
    }
    
    private func createExecution(for program: Program, recipeRepositoryURL: String) {
        Task {
            do {
                let file = try await sync.createExecution(
                    for: program,
                    recipeRepositoryURL: recipeRepositoryURL
                )
                let repositories = refreshExecutionRepositories()
                await MainActor.run {
                    executionRepositories = repositories
                    selectedTab = .executions
                    executionPath = [file.fileURL]
                }
            } catch {
                print("Couldn't create execution: \(error)")
            }
        }
    }
    
    private func executionFile(for fileURL: URL) -> Sync.ExecutionFileDetails? {
        executionRepositories
            .flatMap(\.files)
            .first(where: { $0.fileURL == fileURL })
    }
}


