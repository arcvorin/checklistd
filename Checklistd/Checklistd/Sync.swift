//
//  Sync.swift
//  Checklistd
//
//  Created by Javier Matusevich on 2026-07-17.
//

import Foundation
import KeychainSwift
import SwiftGitX
import OctoKit

class Sync {
    
    private var defaults = UserDefaults()
    var repos: [SyncRepo] = []
    struct SyncRepo: Codable {
        enum SyncRepoEnum: String, Codable {
            case recipe = "recipe"
            case execution = "execution"
        }
        
        let name: String
        let url: String
        let kind: SyncRepoEnum
    }
    
    private lazy var keychain = KeychainSwift()
    private var octokit: Octokit?
    func prepare() {
        keychain.synchronizable = true
        guard let pat = getPAT() else {
            return
        }
        
        octokit = Octokit(TokenConfiguration(pat))
        _ = syncRepos()
    }
    
    init() {
        prepare()
    }
    
    func isAuthenticated() -> Bool {
        return getPAT() != nil
    }
    
    private func getPAT() -> String? {
        return keychain.get("pat")
    }
    
    func setPAT(_ pat: String?) -> Bool {
        guard let pat = pat else {
            return keychain.clear()
        }
        let result = keychain.set(pat, forKey: "pat")
        prepare()
        return result
    }
    
    func listRepos() async -> [OctoKit.Repository]? {
        return try? await octokit?.repositories()
    }
    
    func syncRepos() -> [SyncRepo] {
        if let repos = try? defaults.get(objectType: [SyncRepo].self, forKey: "repos") {
            self.repos = repos
        }
        return repos
    }
    
    func trackRepo(repository: OctoKit.Repository, as kind: SyncRepo.SyncRepoEnum) {
        guard let name = repository.name, let url = repository.cloneURL else {
            return
        }
        var repos = self.syncRepos()
        guard !repos.contains(where: { $0.url == url && $0.kind == kind }) else {
            return
        }
        repos.append(SyncRepo(name: name, url: url, kind: kind))
        try? defaults.set(object: repos, forKey: "repos")
        self.repos = repos
    }
    
    func untrackRepo(repository: OctoKit.Repository) {
        guard let url = repository.cloneURL else {
            return
        }
        var repos = self.syncRepos()
        repos = repos.filter { $0.url != url }
        try? defaults.set(object: repos, forKey: "repos")
        self.repos = repos
    }
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
