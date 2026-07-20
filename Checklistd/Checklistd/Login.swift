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
    @State private var recipePath: [String] = []
    @State private var executionPath: [ExecutionRoute] = []
    @State private var setupStateVersion = 0
    @State private var isContinuing = false
    @State private var isShowingExecutionPicker: Bool = false
    @State private var selectedRecipeRepo: OctoKit.Repository? = nil
    @State private var selectedExecutionRepoURL: String = ""
    @State private var isSyncing = false
    @State private var isCreatingExecution = false
    @State private var isPushingExecution = false
    @State private var statusMessage: String? = nil
    @State private var isShowingExecutionNamePrompt = false
    @State private var newExecutionName = ""
    @State private var pendingExecutionProgram: Program?
    @State private var pendingExecutionRecipeRepositoryURL: String?
    
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
                    
                    NavigationStack(path: $recipePath) {
                        RecipeRepositoryListView(
                            repositories: recipeRepositories,
                            createExecution: createExecution
                        )
                        .navigationTitle("Recipe Repos")
                        .navigationDestination(for: String.self) { repositoryURL in
                            if let repository = recipeRepository(for: repositoryURL) {
                                RecipeListView(
                                    repository: repository,
                                    createExecution: { program in
                                        createExecution(for: program, recipeRepositoryURL: repository.url)
                                    }
                                )
                            } else {
                                Text("Recipe repository not found")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tabItem {
                        Label("Recipes", systemImage: "list.bullet.rectangle")
                    }
                    .tag(AppTab.recipes)
                    
                    NavigationStack(path: $executionPath) {
                        ExecutionRepositoryListView(repositories: executionRepositories)
                            .navigationTitle("Execution Repos")
                            .navigationDestination(for: ExecutionRoute.self) { route in
                                switch route {
                                case .repository(let repositoryURL):
                                    if let repository = executionRepository(for: repositoryURL) {
                                        ExecutionListView(repository: repository)
                                    } else {
                                        Text("Execution repository not found")
                                            .foregroundStyle(.secondary)
                                    }
                                case .file(let fileURL):
                                    if let file = executionFile(for: fileURL) {
                                        ExecutionDetailView(file: file, sync: sync)
                                    } else {
                                        Text("Execution not found")
                                            .foregroundStyle(.secondary)
                                    }
                                case .creating:
                                    LoadingExecutionView(message: statusMessage ?? "Creating execution...")
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
        .alert("Name execution", isPresented: $isShowingExecutionNamePrompt) {
            TextField("Execution name", text: $newExecutionName)
            Button("Create") {
                createPendingExecution()
            }
            Button("Cancel", role: .cancel) {
                clearPendingExecution()
            }
        } message: {
            Text("Give this execution a custom name.")
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                StatusBanner(message: statusMessage, isLoading: isSyncing || isCreatingExecution || isPushingExecution)
                    .padding()
            }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Git identity")
                    .font(.headline)
                LabeledContent("Name") {
                    Text(gitCommitName.isEmpty ? "Not synced" : gitCommitName)
                        .foregroundStyle(gitCommitName.isEmpty ? .secondary : .primary)
                }
                LabeledContent("Email") {
                    Text(gitCommitEmail.isEmpty ? "Not synced" : gitCommitEmail)
                        .foregroundStyle(gitCommitEmail.isEmpty ? .secondary : .primary)
                }
            }
            .padding(.horizontal)
            List(repos, id: \.id) { repo in
                repoPairingRow(repo)
            }
            Spacer()
            Button(syncButtonTitle) {
                if isSetupComplete {
                    syncInBackground(selectRecipesWhenDone: true)
                } else {
                    saveSetup()
                }
            }
            .disabled(isContinuing || isSyncing)
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
                        syncInBackground(selectRecipesWhenDone: false)
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
            statusMessage = "Loading GitHub profile..."
            Task {
                do {
                    let identity = try await sync.syncGitCommitIdentityFromGitHubProfile()
                    await MainActor.run {
                        gitCommitName = identity.name
                        gitCommitEmail = identity.email
                        setupStateVersion += 1
                    }
                } catch {
                    print("Couldn't sync GitHub profile: \(error)")
                    await MainActor.run {
                        statusMessage = "Could not load GitHub profile"
                    }
                    return
                }
                
                await MainActor.run {
                    statusMessage = "Loading repositories..."
                }
                guard let repos = await sync.listRepos() else {
                    statusMessage = nil
                    return
                }
                self.repos = repos
                self.pairs = sync.listPairs()
                refreshRecipeRepositories()
                refreshExecutionRepositories()
                statusMessage = nil
            }
        } else {
            isAuthenticated = false
        }
    }
    
    private func saveSetup() {
        if !newPAT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = sync.setPAT(newPAT)
        }
        
        isAuthenticated = sync.isAuthenticated()
        newPAT = ""
        setupStateVersion += 1
        
        statusMessage = "Loading GitHub profile..."
        Task {
            do {
                let identity = try await sync.syncGitCommitIdentityFromGitHubProfile()
                await MainActor.run {
                    gitCommitName = identity.name
                    gitCommitEmail = identity.email
                    setupStateVersion += 1
                    statusMessage = "Loading repositories..."
                }
            } catch {
                print("Couldn't sync GitHub profile: \(error)")
                await MainActor.run {
                    self.pairs = []
                    self.repos = []
                    self.statusMessage = "Could not load GitHub profile"
                    setupStateVersion += 1
                }
                return
            }
            
            guard let repos = await sync.listRepos() else {
                self.pairs = []
                self.repos = []
                self.statusMessage = "Could not load repositories"
                return
            }
            self.repos = repos
            self.pairs = sync.listPairs()
            refreshRecipeRepositories()
            refreshExecutionRepositories()
            statusMessage = nil
        }
    }
    
    private func syncInBackground(selectRecipesWhenDone: Bool) {
        guard !isSyncing else { return }
        
        isContinuing = true
        isSyncing = true
        statusMessage = "Syncing repositories..."
        recipePath = []
        if selectRecipesWhenDone {
            selectedTab = .recipes
        }
        Task {
            await Task.yield()
            await sync.pullRepos()
            statusMessage = "Loading files..."
            let repositories = refreshRecipeRepositories()
            let executionRepositories = refreshExecutionRepositories()
            await MainActor.run {
                recipeRepositories = repositories
                self.executionRepositories = executionRepositories
                recipePath = []
                if selectRecipesWhenDone {
                    selectedTab = .recipes
                }
                isContinuing = false
                isSyncing = false
                statusMessage = "Sync complete"
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if !isSyncing && !isCreatingExecution && statusMessage == "Sync complete" {
                    statusMessage = nil
                }
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
        pendingExecutionProgram = program
        pendingExecutionRecipeRepositoryURL = recipeRepositoryURL
        newExecutionName = ""
        isShowingExecutionNamePrompt = true
    }
    
    private func createPendingExecution() {
        guard let program = pendingExecutionProgram,
              let recipeRepositoryURL = pendingExecutionRecipeRepositoryURL else {
            clearPendingExecution()
            return
        }
        
        let executionName = newExecutionName
        clearPendingExecution()
        createExecution(for: program, recipeRepositoryURL: recipeRepositoryURL, name: executionName)
    }
    
    private func clearPendingExecution() {
        pendingExecutionProgram = nil
        pendingExecutionRecipeRepositoryURL = nil
        newExecutionName = ""
    }
    
    private func createExecution(for program: Program, recipeRepositoryURL: String, name: String) {
        let creationID = UUID().uuidString
        isCreatingExecution = true
        statusMessage = "Creating execution..."
        selectedTab = .executions
        executionPath = [.creating(creationID)]
        
        Task {
            await Task.yield()
            do {
                let file = try await sync.createExecution(
                    for: program,
                    recipeRepositoryURL: recipeRepositoryURL,
                    name: name
                )
                let repositories = refreshExecutionRepositories()
                await MainActor.run {
                    executionRepositories = repositories
                    selectedTab = .executions
                    executionPath = [.repository(file.repoURL), .file(file.fileURL)]
                    isCreatingExecution = false
                    isPushingExecution = true
                    statusMessage = "Pushing execution..."
                }
                
                await sync.pushRepos()
                
                await MainActor.run {
                    isPushingExecution = false
                    statusMessage = "Execution pushed"
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    if !isSyncing && !isCreatingExecution && !isPushingExecution && statusMessage == "Execution pushed" {
                        statusMessage = nil
                    }
                }
            } catch {
                print("Couldn't create execution: \(error)")
                await MainActor.run {
                    isCreatingExecution = false
                    isPushingExecution = false
                    statusMessage = "Couldn't create execution"
                    executionPath = []
                }
            }
        }
    }
    
    private func executionFile(for fileURL: URL) -> Sync.ExecutionFileDetails? {
        executionRepositories
            .flatMap(\.files)
            .first(where: { $0.fileURL == fileURL })
    }
    
    private func recipeRepository(for repositoryURL: String) -> Sync.RecipeRepositoryDetails? {
        recipeRepositories
            .first(where: { $0.url == repositoryURL })
    }
    
    private func executionRepository(for repositoryURL: String) -> Sync.ExecutionRepositoryDetails? {
        executionRepositories
            .first(where: { $0.url == repositoryURL })
    }
}

private struct StatusBanner: View {
    let message: String
    let isLoading: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(message)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
    }
}
