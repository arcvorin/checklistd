//
//  Sync.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-17.
//

import Foundation
import KeychainSwift
import SwiftGitX
import OctoKit
import VersionedCodable

#if canImport(CryptoKit)
import CryptoKit
#endif

class Sync {
    private enum DefaultsKey {
        static let pairs = "pairs"
        static let gitCommitName = "gitCommitName"
        static let gitCommitEmail = "gitCommitEmail"
    }
    
    struct RecipeRepositoryDetails {
        let name: String
        let url: String
        let files: [Program]
    }
    
    struct ExecutionRepositoryDetails {
        let name: String
        let url: String
        let files: [ExecutionFileDetails]
    }
    
    struct ExecutionFileDetails {
        let repoURL: String
        let fileURL: URL
        let displayName: String
        let execution: Execution
    }
    
    private var defaults = UserDefaults()
    var pairs: [RecipeExecutionPair] = []
    var recipeRepositories: [RecipeRepositoryDetails] = []
    var executionRepositories: [ExecutionRepositoryDetails] = []
    struct RecipeExecutionPair: Codable {
        let recipeName: String
        let recipeURL: String
        let executionName: String
        let executionURL: String
    }
    
    enum SyncError: Error {
        case missingExecutionPair
        case missingExecutionRepository
        case missingGitCommitIdentity
    }
    
    private lazy var keychain = KeychainSwift()
    private var octokit: Octokit?
    func prepare() {
        keychain.synchronizable = true
        guard let pat = getPAT() else {
            return
        }
        
        octokit = Octokit(TokenConfiguration(pat))
        _ = syncPairs()
    }
    
    init() {
        prepare()
    }
    
    func isAuthenticated() -> Bool {
        return getPAT() != nil
    }
    
    private func getPAT() -> String? {
        guard let pat = keychain.get("pat")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pat.isEmpty else {
            return nil
        }
        
        return pat
    }
    
    func setPAT(_ pat: String?) -> Bool {
        guard let pat = pat else {
            return keychain.clear()
        }
        let result = keychain.set(pat, forKey: "pat")
        prepare()
        return result
    }
    
    func gitCommitName() -> String {
        defaults.string(forKey: DefaultsKey.gitCommitName) ?? ""
    }
    
    func gitCommitEmail() -> String {
        defaults.string(forKey: DefaultsKey.gitCommitEmail) ?? ""
    }
    
    func setGitCommitIdentity(name: String, email: String) {
        defaults.set(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.gitCommitName
        )
        defaults.set(
            email.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.gitCommitEmail
        )
    }
    
    func gitCommitIdentity() -> GitCommitIdentity? {
        let name = gitCommitName().trimmingCharacters(in: .whitespacesAndNewlines)
        let email = gitCommitEmail().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty, !email.isEmpty else {
            return nil
        }
        
        return GitCommitIdentity(name: name, email: email)
    }
    
    func listRepos() async -> [OctoKit.Repository]? {
        return try? await octokit?.repositories()
    }
    
    func syncPairs() -> [RecipeExecutionPair] {
        if let loadedPairs = try? defaults.get(objectType: [RecipeExecutionPair].self, forKey: DefaultsKey.pairs) {
            self.pairs = loadedPairs
        }
        return pairs
    }
    
    func setPair(recipe: OctoKit.Repository, execution: OctoKit.Repository) {
        guard let recipeName = recipe.name,
              let recipeURL = recipe.cloneURL,
              let executionName = execution.name,
              let executionURL = execution.cloneURL else {
            return
        }
        var pairs = self.syncPairs()
        pairs.removeAll(where: { $0.recipeURL == recipeURL })
        let newPair = RecipeExecutionPair(recipeName: recipeName, recipeURL: recipeURL, executionName: executionName, executionURL: executionURL)
        pairs.append(newPair)
        try? defaults.set(object: pairs, forKey: DefaultsKey.pairs)
        self.pairs = pairs
    }
    
    func removePair(for recipe: OctoKit.Repository) {
        guard let recipeURL = recipe.cloneURL else {
            return
        }
        var pairs = self.syncPairs()
        pairs.removeAll(where: { $0.recipeURL == recipeURL })
        try? defaults.set(object: pairs, forKey: DefaultsKey.pairs)
        self.pairs = pairs
    }
    
    func listPairs() -> [RecipeExecutionPair] {
        return syncPairs()
    }
    
    @discardableResult
    func listRecipes() -> [RecipeRepositoryDetails] {
        let pairs = syncPairs()
        let recipeRepoURLs = Set(pairs.map(\.recipeURL))
        let recipeRepos = recipeRepoURLs.map { urlString in
            let name = URL(string: urlString)?.deletingPathExtension().lastPathComponent ?? urlString
            return (name: name, url: urlString)
        }
        let repos: [(name: String, url: String, files: [Program])] = recipeRepos.map{
            repo in
            let urlString = repo.url
            let repoDir = localRepoDirectory(for: urlString)
            guard let fileURLs = FileManager.default.enumerator(
                at: repoDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                print("Couldn't list files in \(repoDir) for \(urlString)")
                return (name: repo.name, url: repo.url, files: Array<Program>())
            }
            
            let jsonFiles = fileURLs.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
            print(jsonFiles.map(\.lastPathComponent))
            
            let fileContents: [Program] = jsonFiles.flatMap { fileURL in
                do {
                    print(fileURL.absoluteString)
                    let data = try Data(contentsOf: fileURL)
                    let program = try JSONDecoder.checklistd.decode(versioned: Program.self, from: data)
                    return [program]
                } catch {
                    print("Couldn't read recipe file \(fileURL.path): \(error)")
                    return Array<Program>()
                }
            }
            return (name: repo.name, url: repo.url, files: fileContents)
        }
        
        let mappedRepos = repos.map({
            RecipeRepositoryDetails(name: $0.name, url: $0.url, files: $0.files)
        })
        
        self.recipeRepositories = mappedRepos
        return mappedRepos
    }
    
    @discardableResult
    func listExecutions() -> [ExecutionRepositoryDetails] {
        let pairs = syncPairs()
        let executionRepoURLs = Set(pairs.map(\.executionURL))
        let executionRepos = executionRepoURLs.map { urlString in
            let name = URL(string: urlString)?.deletingPathExtension().lastPathComponent ?? urlString
            return (name: name, url: urlString)
        }
        
        let repos: [ExecutionRepositoryDetails] = executionRepos.map { repo in
            let repoDir = localRepoDirectory(for: repo.url)
            guard let fileURLs = FileManager.default.enumerator(
                at: repoDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                print("Couldn't list execution files in \(repoDir) for \(repo.url)")
                return ExecutionRepositoryDetails(name: repo.name, url: repo.url, files: [])
            }
            
            let files = fileURLs
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "json" }
                .compactMap { fileURL -> ExecutionFileDetails? in
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let execution = try JSONDecoder.checklistd.decode(Execution.self, from: data)
                        return ExecutionFileDetails(
                            repoURL: repo.url,
                            fileURL: fileURL,
                            displayName: fileURL.deletingPathExtension().lastPathComponent,
                            execution: execution
                        )
                    } catch {
                        print("Couldn't read execution file \(fileURL.path): \(error)")
                        return nil
                    }
                }
                .sorted { $0.fileURL.lastPathComponent > $1.fileURL.lastPathComponent }
            
            return ExecutionRepositoryDetails(name: repo.name, url: repo.url, files: files)
        }
        
        executionRepositories = repos
        return repos
    }
    
    func createExecution(
        for program: Program,
        recipeRepositoryURL: String,
        name: String
    ) async throws -> ExecutionFileDetails {
        guard let pair = syncPairs().first(where: { $0.recipeURL == recipeRepositoryURL }) else {
            throw SyncError.missingExecutionPair
        }
        
        let executionRepoDir = localRepoDirectory(for: pair.executionURL)
        if !FileManager.default.fileExists(atPath: executionRepoDir.path) {
            await pullRepos()
        }
        
        guard FileManager.default.fileExists(atPath: executionRepoDir.path) else {
            throw SyncError.missingExecutionRepository
        }
        
        guard let identity = gitCommitIdentity() else {
            throw SyncError.missingGitCommitIdentity
        }
        
        let createdAt = Date()
        var execution = Execution(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdByName: identity.name,
            createdByEmail: identity.email,
            createdAt: createdAt,
            updatedAt: createdAt,
            program: program
        )
        execution.recordCreation(actor: identity)
        try execution.run(actor: identity)
        
        let fileURL = executionRepoDir.appendingPathComponent(
            executionFileName(for: program, executionName: execution.name),
            isDirectory: false
        )
        try write(execution: execution, to: fileURL)
        try writeMarkdown(for: execution, jsonFileURL: fileURL)
        let details = ExecutionFileDetails(
            repoURL: pair.executionURL,
            fileURL: fileURL,
            displayName: fileURL.deletingPathExtension().lastPathComponent,
            execution: execution
        )
        
        _ = listExecutions()
        return details
    }
    
    func saveExecution(_ execution: Execution, to fileURL: URL) async {
        do {
            var updatedExecution = execution
            updatedExecution.updatedAt = Date()
            try write(execution: updatedExecution, to: fileURL)
            try writeMarkdown(for: updatedExecution, jsonFileURL: fileURL)
            _ = listExecutions()
            Task {
                await pushRepos()
            }
        } catch {
            print("Couldn't save execution file \(fileURL.path): \(error)")
        }
    }
    
    private func write(execution: Execution, to fileURL: URL) throws {
        let data = try JSONEncoder.checklistd.encode(execution)
        try data.write(to: fileURL, options: [.atomic])
    }
    
    private func writeMarkdown(for execution: Execution, jsonFileURL: URL) throws {
        let markdownURL = jsonFileURL.deletingPathExtension().appendingPathExtension("md")
        let data = Data(execution.markdownAudit().utf8)
        try data.write(to: markdownURL, options: [.atomic])
    }
    
    private func executionFileName(for program: Program, executionName: String) -> String {
        let timestamp = DateFormatter.checklistdExecutionFileTimestamp.string(from: Date())
        let timestampHash = String(sha256Hex(of: timestamp).prefix(8))
        let userName = safeFileName(gitCommitName(), fallback: "user")
        let safeExecutionName = safeFileName(executionName, fallback: "")
        
        guard !safeExecutionName.isEmpty else {
            return "\(userName)-\(timestamp)-\(timestampHash).json"
        }
        
        return "\(userName)-\(safeExecutionName)-\(timestamp)-\(timestampHash).json"
    }
    
    private func safeFileName(_ string: String, fallback: String = "user") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = string
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? fallback : collapsed
    }
    
    func pushRepos() async {
        guard let pat = getPAT() else {
            print("Git push skipped: no PAT available")
            return
        }
        guard let identity = gitCommitIdentity() else {
            print("Git push skipped: git commit name and email are required")
            return
        }
        
        let executionRepoURLs = Set(syncPairs().map(\.executionURL))
        
        for urlString in executionRepoURLs {
            let repoDir = localRepoDirectory(for: urlString)
            
            guard FileManager.default.fileExists(atPath: repoDir.path) else {
                print("Git push skipped for \(urlString): local repository does not exist")
                continue
            }
            
            do {
                let localRepo = try SwiftGitX.Repository(at: repoDir)
                let _ = try await localRepo.pull(
                    conflictStrategy: .keepLocalChanges,
                    pat: pat,
                    commitIdentity: identity
                )
                let _ = try await localRepo.commitAll(
                    message: "Update execution state",
                    identity: identity
                )
                try await localRepo.push(pat: pat)
            } catch {
                print("Git push failed for \(urlString): \(error)")
            }
        }
    }
    
    func pullRepos() async {
        guard let pat = getPAT() else {
            print("Git pull skipped: no PAT available")
            return
        }
        
        let pairs = self.syncPairs()
        let repoURLs = Set(pairs.flatMap { [$0.recipeURL, $0.executionURL] })
        let repoURLsAnnotated = repoURLs.map({url in (url,
            pairs.contains(where: {$0.recipeURL == url}),
            pairs.contains(where: {$0.executionURL == url})
        )})
        
        for urlAnnotated in repoURLsAnnotated {
            let urlString = urlAnnotated.0
            let isRecipe = urlAnnotated.1
            let isExecution = urlAnnotated.2
            
            guard let remoteURL = URL(string: urlString) else { continue }
            let repoDir = localRepoDirectory(for: urlString)
            
            do {
                if !FileManager.default.fileExists(atPath: repoDir.path) {
                    // First-time clone
                    let _ = try await SwiftGitX.Repository.clone(from: remoteURL, to: repoDir, pat: pat)
                } else {
                    let localRepo = try SwiftGitX.Repository(at: repoDir)
                    _ = try await localRepo.pull(
                        conflictStrategy: isExecution && !isRecipe ? .keepLocalChanges : .takeRemoteChanges,
                        pat: pat,
                        commitIdentity: gitCommitIdentity()
                    )
                }
            } catch {
                print("Git clone failed for \(urlString): \(error)")
            }
        }
    }
    
    private func localRepoDirectory(for urlString: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let baseDir = (appSupport ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!)
            .appendingPathComponent("Checklistd")
            .appendingPathComponent("Repos")
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        return baseDir.appendingPathComponent(sha256Hex(of: urlString), isDirectory: true)
    }
    
    private func sha256Hex(of string: String) -> String {
        guard let data = string.data(using: .utf8) else { return String(string.hashValue) }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback: deterministic but less secure hash
        var hasher = Hasher()
        hasher.combine(string)
        return String(hasher.finalize())
        #endif
    }
}

private extension DateFormatter {
    static let checklistdExecutionFileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()
}

public extension UserDefaults {

    /// Set Codable object into UserDefaults
    ///
    /// - Parameters:
    ///   - object: Codable Object
    ///   - forKey: Key string
    /// - Throws: UserDefaults Error
    public func set<T: Codable>(object: T, forKey: String) throws {

        let jsonData = try JSONEncoder().encode(object)

        set(jsonData, forKey: forKey)
    }

    /// Get Codable object into UserDefaults
    ///
    /// - Parameters:
    ///   - object: Codable Object
    ///   - forKey: Key string
    /// - Throws: UserDefaults Error
    public func get<T: Codable>(objectType: T.Type, forKey: String) throws -> T? {

        guard let result = value(forKey: forKey) as? Data else {
            return nil
        }

        return try JSONDecoder().decode(objectType, from: result)
    }
}
