import Foundation
import SwiftGitX
import libgit2

private struct PullError: Swift.Error, CustomStringConvertible {
    let description: String
}

private struct GitCredentials {
    let username: String
    let password: String

    init(pat: String) {
        username = "x-access-token"
        password = pat
    }

    func withCallbackPayload<T>(_ body: (UnsafeMutableRawPointer) throws -> T) rethrows -> T {
        let payload = UnsafeMutablePointer<GitCredentials>.allocate(capacity: 1)
        payload.initialize(to: self)
        defer {
            payload.deinitialize(count: 1)
            payload.deallocate()
        }

        return try body(UnsafeMutableRawPointer(payload))
    }
}

private let gitCredentialsCallback: git_credential_acquire_cb = { out, _, usernameFromURL, allowedTypes, payload in
    guard
        allowedTypes & GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue != 0,
        let out,
        let payload
    else {
        return GIT_PASSTHROUGH.rawValue
    }

    let credentials = payload.assumingMemoryBound(to: GitCredentials.self).pointee
    let username = usernameFromURL.map { String(cString: $0) } ?? credentials.username

    return username.withCString { usernamePointer in
        credentials.password.withCString { passwordPointer in
            git_credential_userpass_plaintext_new(out, usernamePointer, passwordPointer)
        }
    }
}

public enum PullConflictStrategy: Sendable {
    case keepLocalChanges
    case takeRemoteChanges

    fileprivate var gitFileFavor: git_merge_file_favor_t {
        switch self {
        case .keepLocalChanges:
            return GIT_MERGE_FILE_FAVOR_OURS
        case .takeRemoteChanges:
            return GIT_MERGE_FILE_FAVOR_THEIRS
        }
    }
}

public enum PullResult: Sendable {
    case upToDate
    case fastForward(String)
    case merged(String)
}

public struct GitCommitIdentity: Sendable {
    let name: String
    let email: String
}

public extension Repository {
    static func clone(
        from remoteURL: URL,
        to localURL: URL,
        pat: String
    ) async throws -> Repository {
        try SwiftGitXRuntime.initialize()
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var cloneOptions = git_clone_options()
        git_clone_options_init(&cloneOptions, UInt32(GIT_CLONE_OPTIONS_VERSION))
        cloneOptions.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        cloneOptions.fetch_opts.callbacks.credentials = gitCredentialsCallback

        let credentials = GitCredentials(pat: pat)
        return try credentials.withCallbackPayload { payload in
            cloneOptions.fetch_opts.callbacks.payload = payload

            var repositoryPointer: OpaquePointer?
            let result = git_clone(
                &repositoryPointer,
                remoteURL.absoluteString,
                localURL.path,
                &cloneOptions
            )
            try GitPullHandle.throwIfGitError(result)

            guard let repositoryPointer else {
                throw PullError(description: "Could not clone repository from \(remoteURL.absoluteString).")
            }
            git_repository_free(repositoryPointer)

            return try Repository(at: localURL, createIfNotExists: false)
        }
    }

    nonisolated func pull(
        remoteName: String = "origin",
        branchName: String? = nil,
        conflictStrategy: PullConflictStrategy = .keepLocalChanges,
        pat: String? = nil,
        commitIdentity: GitCommitIdentity? = nil
    ) async throws -> PullResult {
        let handle = try GitPullHandle(repositoryURL: workingDirectory)
        defer { handle.close() }

        try handle.fetch(remoteName: remoteName, pat: pat)

        return try handle.pull(
            remoteName: remoteName,
            branchName: branchName,
            conflictStrategy: conflictStrategy,
            commitIdentity: commitIdentity
        )
    }

    nonisolated func commitAll(
        message: String,
        identity: GitCommitIdentity
    ) async throws -> String? {
        let handle = try GitPullHandle(repositoryURL: workingDirectory)
        defer { handle.close() }

        return try handle.commitAll(message: message, identity: identity)
    }

    nonisolated func push(
        remoteName: String = "origin",
        pat: String
    ) async throws {
        let handle = try GitPullHandle(repositoryURL: workingDirectory)
        defer { handle.close() }

        try handle.push(remoteName: remoteName, pat: pat)
    }
}

private final class GitPullHandle {
    private let repositoryPointer: OpaquePointer
    private var isClosed = false

    init(repositoryURL: URL) throws {
        try SwiftGitXRuntime.initialize()

        do {
            var pointer: OpaquePointer?
            let result = git_repository_open(&pointer, repositoryURL.path)
            try GitPullHandle.throwIfGitError(result)

            guard let pointer else {
                throw PullError(description: "Could not open repository at \(repositoryURL.path).")
            }

            repositoryPointer = pointer
        } catch {
            _ = try? SwiftGitXRuntime.shutdown()
            throw error
        }
    }

    func close() {
        guard !isClosed else {
            return
        }

        git_repository_free(repositoryPointer)
        _ = try? SwiftGitXRuntime.shutdown()
        isClosed = true
    }

    deinit {
        close()
    }

    func fetch(remoteName: String, pat: String?) throws {
        let remotePointer = try lookupRemote(named: remoteName)
        defer { git_remote_free(remotePointer) }

        if let pat {
            var fetchOptions = git_fetch_options()
            git_fetch_options_init(&fetchOptions, UInt32(GIT_FETCH_OPTIONS_VERSION))
            fetchOptions.callbacks.credentials = gitCredentialsCallback

            let credentials = GitCredentials(pat: pat)
            try credentials.withCallbackPayload { payload in
                fetchOptions.callbacks.payload = payload
                let result = git_remote_fetch(remotePointer, nil, &fetchOptions, nil)
                try Self.throwIfGitError(result)
            }
        } else {
            let result = git_remote_fetch(remotePointer, nil, nil, nil)
            try Self.throwIfGitError(result)
        }
    }

    func push(remoteName: String, pat: String) throws {
        let currentBranch = try currentBranchReference()
        defer { git_reference_free(currentBranch) }

        let remotePointer = try lookupRemote(named: remoteName)
        defer { git_remote_free(remotePointer) }

        let refspec = try pushRefspec(for: currentBranch, remoteName: remoteName)

        var pushOptions = git_push_options()
        git_push_options_init(&pushOptions, UInt32(GIT_PUSH_OPTIONS_VERSION))
        pushOptions.callbacks.credentials = gitCredentialsCallback

        let credentials = GitCredentials(pat: pat)
        try credentials.withCallbackPayload { payload in
            pushOptions.callbacks.payload = payload
            
            try refspec.withCString { refspecPointer in
                var mutableRefspecPointer: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: refspecPointer)
                try withUnsafeMutablePointer(to: &mutableRefspecPointer) { refspecsPointer in
                    var refspecArray = git_strarray(
                        strings: refspecsPointer,
                        count: 1
                    )
                    let result = git_remote_push(remotePointer, &refspecArray, &pushOptions)
                    try Self.throwIfGitError(result)
                }
            }
        }
    }

    func pull(
        remoteName: String,
        branchName: String?,
        conflictStrategy: PullConflictStrategy,
        commitIdentity: GitCommitIdentity?
    ) throws -> PullResult {
        let localBranchReference = try currentBranchReference()
        defer { git_reference_free(localBranchReference) }

        let remoteBranchReference = try pullReference(
            for: localBranchReference,
            remoteName: remoteName,
            branchName: branchName
        )
        defer { git_reference_free(remoteBranchReference) }

        return try mergeFetchedBranch(
            remoteBranchReference,
            localBranchReference: localBranchReference,
            conflictStrategy: conflictStrategy,
            commitIdentity: commitIdentity
        )
    }

    func commitAll(message: String, identity: GitCommitIdentity) throws -> String? {
        let index = try repositoryIndex()
        defer { git_index_free(index) }

        let addResult = git_index_add_all(index, nil, UInt32(GIT_INDEX_ADD_DEFAULT.rawValue), nil, nil)
        try Self.throwIfGitError(addResult)

        var treeOID = git_oid()
        let writeTreeResult = git_index_write_tree(&treeOID, index)
        try Self.throwIfGitError(writeTreeResult)

        let parentCommit = try? headCommit()
        defer {
            if let parentCommit {
                git_commit_free(parentCommit)
            }
        }

        if let parentCommit, let parentTreeOID = git_commit_tree_id(parentCommit) {
            var parentTreeOIDValue = parentTreeOID.pointee
            var treeOIDValue = treeOID
            if git_oid_equal(&parentTreeOIDValue, &treeOIDValue) == 1 {
                return nil
            }
        }

        let writeIndexResult = git_index_write(index)
        try Self.throwIfGitError(writeIndexResult)

        var treePointer: OpaquePointer?
        let treeLookupResult = git_tree_lookup(&treePointer, repositoryPointer, &treeOID)
        try Self.throwIfGitError(treeLookupResult)

        guard let treePointer else {
            throw PullError(description: "Could not look up commit tree.")
        }
        defer { git_tree_free(treePointer) }

        let signaturePointer = try makeSignature(identity: identity)
        defer { git_signature_free(signaturePointer) }

        var parentPointers: [OpaquePointer?] = parentCommit.map { [$0] } ?? []
        var commitOID = git_oid()
        let referenceName = "HEAD"

        try referenceName.withCString { referenceNamePointer in
            try message.withCString { messagePointer in
                let result = git_commit_create(
                    &commitOID,
                    repositoryPointer,
                    referenceNamePointer,
                    signaturePointer,
                    signaturePointer,
                    nil,
                    messagePointer,
                    treePointer,
                    parentPointers.count,
                    &parentPointers
                )
                try Self.throwIfGitError(result)
            }
        }

        return hexString(for: commitOID)
    }

    private func mergeFetchedBranch(
        _ remoteBranchReference: OpaquePointer,
        localBranchReference: OpaquePointer,
        conflictStrategy: PullConflictStrategy,
        commitIdentity: GitCommitIdentity?
    ) throws -> PullResult {
        let annotatedCommit = try makeAnnotatedCommit(from: remoteBranchReference)
        defer { git_annotated_commit_free(annotatedCommit) }

        let analysis = try analyzeMerge(for: annotatedCommit)

        if analysis.isUpToDate {
            return .upToDate
        }

        if analysis.isFastForward {
            let oid = try fastForwardCurrentBranch(
                localBranchReference: localBranchReference,
                to: remoteBranchReference,
                conflictStrategy: conflictStrategy
            )
            return .fastForward(hexString(for: oid))
        }

        try performMerge(
            with: annotatedCommit,
            conflictStrategy: conflictStrategy
        )

        let index = try repositoryIndex()

        if git_index_has_conflicts(index) == 1 {
            git_index_free(index)
            try? cleanupMergeState()
            throw PullError(
                description:
                "Pull resulted in unresolved conflicts even though a " +
                    "conflict strategy was provided."
            )
        }

        let mergeCommitOID = try createMergeCommit(
            localBranchReference: localBranchReference,
            remoteBranchReference: remoteBranchReference,
            commitIdentity: commitIdentity
        )

        git_index_free(index)
        try cleanupMergeState()

        return .merged(hexString(for: mergeCommitOID))
    }

    private func currentBranchReference() throws -> OpaquePointer {
        var headPointer: OpaquePointer?
        let result = git_repository_head(&headPointer, repositoryPointer)
        try Self.throwIfGitError(result)

        guard let headPointer else {
            throw PullError(description: "Could not read repository HEAD.")
        }

        guard git_reference_is_branch(headPointer) == 1 else {
            git_reference_free(headPointer)
            throw PullError(description: "HEAD is detached; pull requires a checked out branch.")
        }

        return headPointer
    }
    
    private func pullReference(
        for localBranchReference: OpaquePointer,
        remoteName: String,
        branchName: String?
    ) throws -> OpaquePointer {
        if let branchName {
            return try lookupResolvedReference(named: "refs/remotes/\(remoteName)/\(branchName)")
        }
        
        if let upstreamReference = try lookupUpstreamReference(for: localBranchReference) {
            return upstreamReference
        }
        
        let localBranchName = try shorthand(for: localBranchReference)
        let matchingRemoteReferenceName = "refs/remotes/\(remoteName)/\(localBranchName)"
        
        if let matchingRemoteReference = try? lookupResolvedReference(named: matchingRemoteReferenceName) {
            return matchingRemoteReference
        }
        
        if let defaultRemoteReference = try? lookupResolvedReference(named: "refs/remotes/\(remoteName)/HEAD") {
            return defaultRemoteReference
        }
        
        throw PullError(
            description:
            "Could not find an upstream branch, \(matchingRemoteReferenceName), " +
                "or refs/remotes/\(remoteName)/HEAD to pull from."
        )
    }
    
    private func lookupUpstreamReference(for localBranchReference: OpaquePointer) throws -> OpaquePointer? {
        var upstreamReference: OpaquePointer?
        let result = git_branch_upstream(&upstreamReference, localBranchReference)
        
        if result == GIT_ENOTFOUND.rawValue {
            git_error_clear()
            return nil
        }
        
        try Self.throwIfGitError(result)
        
        guard let upstreamReference else {
            return nil
        }
        
        return try resolveReference(upstreamReference)
    }

    private func shorthand(for reference: OpaquePointer) throws -> String {
        guard let shorthand = git_reference_shorthand(reference) else {
            throw PullError(description: "Could not determine branch shorthand.")
        }

        return String(cString: shorthand)
    }

    private func lookupReference(named name: String) throws -> OpaquePointer {
        var referencePointer: OpaquePointer?

        try name.withCString { namePointer in
            let result = git_reference_lookup(
                &referencePointer,
                repositoryPointer,
                namePointer
            )
            try Self.throwIfGitError(result)
        }

        guard let referencePointer else {
            throw PullError(description: "Could not find reference named \(name).")
        }

        return referencePointer
    }
    
    private func lookupResolvedReference(named name: String) throws -> OpaquePointer {
        let reference = try lookupReference(named: name)
        return try resolveReference(reference)
    }
    
    private func resolveReference(_ reference: OpaquePointer) throws -> OpaquePointer {
        var resolvedReference: OpaquePointer?
        let result = git_reference_resolve(&resolvedReference, reference)
        git_reference_free(reference)
        try Self.throwIfGitError(result)
        
        guard let resolvedReference else {
            throw PullError(description: "Could not resolve reference.")
        }
        
        return resolvedReference
    }

    private func lookupRemote(named name: String) throws -> OpaquePointer {
        var remotePointer: OpaquePointer?

        try name.withCString { namePointer in
            let result = git_remote_lookup(&remotePointer, repositoryPointer, namePointer)
            try Self.throwIfGitError(result)
        }

        guard let remotePointer else {
            throw PullError(description: "Could not find remote named \(name).")
        }

        return remotePointer
    }

    private func pushRefspec(for localBranchReference: OpaquePointer, remoteName: String) throws -> String {
        let remoteBranchName = try pushTargetBranchName(
            for: localBranchReference,
            remoteName: remoteName
        )
        return "HEAD:refs/heads/\(remoteBranchName)"
    }
    
    private func pushTargetBranchName(
        for localBranchReference: OpaquePointer,
        remoteName: String
    ) throws -> String {
        if let upstreamReference = try lookupUpstreamReference(for: localBranchReference) {
            defer { git_reference_free(upstreamReference) }
            if let branchName = remoteBranchName(for: upstreamReference, remoteName: remoteName) {
                return branchName
            }
        }
        
        let localBranchName = try shorthand(for: localBranchReference)
        if let matchingRemoteReference = try? lookupResolvedReference(named: "refs/remotes/\(remoteName)/\(localBranchName)") {
            git_reference_free(matchingRemoteReference)
            return localBranchName
        }
        
        if let defaultRemoteReference = try? lookupResolvedReference(named: "refs/remotes/\(remoteName)/HEAD") {
            defer { git_reference_free(defaultRemoteReference) }
            if let branchName = remoteBranchName(for: defaultRemoteReference, remoteName: remoteName) {
                return branchName
            }
        }

        if let remoteDefaultBranchName = try remoteDefaultBranchName(remoteName: remoteName) {
            return remoteDefaultBranchName
        }
        
        return localBranchName
    }

    private func remoteDefaultBranchName(remoteName: String) throws -> String? {
        let remotePointer = try lookupRemote(named: remoteName)
        defer { git_remote_free(remotePointer) }

        var buffer = git_buf(ptr: nil, reserved: 0, size: 0)
        let result = git_remote_default_branch(&buffer, remotePointer)
        defer { git_buf_dispose(&buffer) }

        if result == GIT_ENOTFOUND.rawValue {
            git_error_clear()
            return nil
        }

        try Self.throwIfGitError(result)

        guard let pointer = buffer.ptr else {
            return nil
        }

        let referenceName = String(cString: pointer)
        let prefix = "refs/heads/"
        guard referenceName.hasPrefix(prefix) else {
            return nil
        }

        return String(referenceName.dropFirst(prefix.count))
    }
    
    private func remoteBranchName(for reference: OpaquePointer, remoteName: String) -> String? {
        guard let namePointer = git_reference_name(reference) else {
            return nil
        }
        
        let name = String(cString: namePointer)
        let prefix = "refs/remotes/\(remoteName)/"
        guard name.hasPrefix(prefix) else {
            return nil
        }
        
        let branchName = String(name.dropFirst(prefix.count))
        return branchName == "HEAD" ? nil : branchName
    }

    private func makeAnnotatedCommit(from reference: OpaquePointer) throws -> OpaquePointer {
        var annotatedCommitPointer: OpaquePointer?

        let result = git_annotated_commit_from_ref(
            &annotatedCommitPointer,
            repositoryPointer,
            reference
        )
        try Self.throwIfGitError(result)

        guard let annotatedCommitPointer else {
            throw PullError(description: "Could not create annotated commit from reference.")
        }

        return annotatedCommitPointer
    }

    private func analyzeMerge(for annotatedCommit: OpaquePointer) throws -> MergeAnalysis {
        var analysis = git_merge_analysis_t(rawValue: 0)
        var preference = git_merge_preference_t(rawValue: 0)
        var annotatedCommits: [OpaquePointer?] = [annotatedCommit]

        let result = git_merge_analysis(
            &analysis,
            &preference,
            repositoryPointer,
            &annotatedCommits,
            annotatedCommits.count
        )
        try Self.throwIfGitError(result)

        return MergeAnalysis(analysis: analysis, preference: preference)
    }

    private func fastForwardCurrentBranch(
        localBranchReference: OpaquePointer,
        to remoteBranchReference: OpaquePointer,
        conflictStrategy: PullConflictStrategy
    ) throws -> git_oid {
        let oldOID = try referenceTargetOID(for: localBranchReference)
        let targetOID = try referenceTargetOID(for: remoteBranchReference)
        let branchName = try fullReferenceName(for: localBranchReference)
        let updateMessage = "pull: fast-forward"
        
        do {
            try setReference(localBranchReference, to: targetOID, message: updateMessage)
            try setHead(to: branchName)
            try checkoutHead(conflictStrategy: conflictStrategy)
        } catch {
            try? setReference(localBranchReference, to: oldOID, message: "pull: restore failed fast-forward")
            try? setHead(to: branchName)
            throw error
        }

        return targetOID
    }
    
    private func setReference(_ reference: OpaquePointer, to oid: git_oid, message: String) throws {
        var updatedReference: OpaquePointer?
        var rawOID = oid
        
        try message.withCString { messagePointer in
            let result = git_reference_set_target(
                &updatedReference,
                reference,
                &rawOID,
                messagePointer
            )
            try Self.throwIfGitError(result)
        }
        
        if let updatedReference {
            git_reference_free(updatedReference)
        }
    }
    
    private func setHead(to branchName: String) throws {
        try branchName.withCString { branchNamePointer in
            let result = git_repository_set_head(repositoryPointer, branchNamePointer)
            try Self.throwIfGitError(result)
        }
    }
    
    private func checkoutHead(conflictStrategy: PullConflictStrategy) throws {
        var checkoutOptions = git_checkout_options()
        git_checkout_options_init(
            &checkoutOptions,
            UInt32(GIT_CHECKOUT_OPTIONS_VERSION)
        )
        
        switch conflictStrategy {
        case .keepLocalChanges:
            checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
        case .takeRemoteChanges:
            checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
        }
        
        let checkoutResult = git_checkout_head(repositoryPointer, &checkoutOptions)
        try Self.throwIfGitError(checkoutResult)
    }

    private func performMerge(
        with annotatedCommit: OpaquePointer,
        conflictStrategy: PullConflictStrategy
    ) throws {
        var mergeOptions = git_merge_options()
        git_merge_options_init(&mergeOptions, UInt32(GIT_MERGE_OPTIONS_VERSION))
        mergeOptions.file_favor = conflictStrategy.gitFileFavor

        var checkoutOptions = git_checkout_options()
        git_checkout_options_init(
            &checkoutOptions,
            UInt32(GIT_CHECKOUT_OPTIONS_VERSION)
        )
        checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

        var annotatedCommits: [OpaquePointer?] = [annotatedCommit]

        let result = git_merge(
            repositoryPointer,
            &annotatedCommits,
            annotatedCommits.count,
            &mergeOptions,
            &checkoutOptions
        )
        try Self.throwIfGitError(result)
    }

    private func createMergeCommit(
        localBranchReference: OpaquePointer,
        remoteBranchReference: OpaquePointer,
        commitIdentity: GitCommitIdentity?
    ) throws -> git_oid {
        let index = try repositoryIndex()
        defer { git_index_free(index) }

        var treeOID = git_oid()
        let writeTreeResult = git_index_write_tree(&treeOID, index)
        try Self.throwIfGitError(writeTreeResult)

        let writeIndexResult = git_index_write(index)
        try Self.throwIfGitError(writeIndexResult)

        var treePointer: OpaquePointer?
        let treeLookupResult = git_tree_lookup(&treePointer, repositoryPointer, &treeOID)
        try Self.throwIfGitError(treeLookupResult)

        guard let treePointer else {
            throw PullError(description: "Could not look up merged tree.")
        }
        defer { git_tree_free(treePointer) }

        let localOID = try referenceTargetOID(for: localBranchReference)
        let remoteOID = try referenceTargetOID(for: remoteBranchReference)

        let localCommit = try lookupCommit(oid: localOID)
        defer { git_commit_free(localCommit) }

        let remoteCommit = try lookupCommit(oid: remoteOID)
        defer { git_commit_free(remoteCommit) }

        let signaturePointer = try makeSignature(identity: commitIdentity)
        defer { git_signature_free(signaturePointer) }

        let localName = try shorthand(for: localBranchReference)
        let remoteName = try shorthand(for: remoteBranchReference)
        let message = "Merge \(remoteName) into \(localName)"

        var newCommitOID = git_oid()
        var parentPointers: [OpaquePointer?] = [
            localCommit,
            remoteCommit,
        ]

        let referenceName = "HEAD"

        try referenceName.withCString { referenceNamePointer in
            try message.withCString { messagePointer in
                let result = git_commit_create(
                    &newCommitOID,
                    repositoryPointer,
                    referenceNamePointer,
                    signaturePointer,
                    signaturePointer,
                    nil,
                    messagePointer,
                    treePointer,
                    parentPointers.count,
                    &parentPointers
                )
                try Self.throwIfGitError(result)
            }
        }

        return newCommitOID
    }

    private func makeSignature(identity: GitCommitIdentity?) throws -> UnsafeMutablePointer<git_signature> {
        var signaturePointer: UnsafeMutablePointer<git_signature>?

        if let identity {
            let result = identity.name.withCString { namePointer in
                identity.email.withCString { emailPointer in
                    git_signature_now(&signaturePointer, namePointer, emailPointer)
                }
            }
            try Self.throwIfGitError(result)
        } else {
            let result = git_signature_default(&signaturePointer, repositoryPointer)
            try Self.throwIfGitError(result)
        }

        guard let signaturePointer else {
            throw PullError(description: "Could not create git signature.")
        }

        return signaturePointer
    }

    private func repositoryIndex() throws -> OpaquePointer {
        var indexPointer: OpaquePointer?

        let result = git_repository_index(&indexPointer, repositoryPointer)
        try Self.throwIfGitError(result)

        guard let indexPointer else {
            throw PullError(description: "Could not load repository index.")
        }

        return indexPointer
    }

    private func referenceTargetOID(for reference: OpaquePointer) throws -> git_oid {
        guard let oidPointer = git_reference_target(reference) else {
            throw PullError(description: "Reference does not point directly to a commit.")
        }

        return oidPointer.pointee
    }

    private func lookupCommit(oid: git_oid) throws -> OpaquePointer {
        var commitPointer: OpaquePointer?
        var rawOID = oid

        let result = git_commit_lookup(&commitPointer, repositoryPointer, &rawOID)
        try Self.throwIfGitError(result)

        guard let commitPointer else {
            throw PullError(description: "Could not look up commit \(hexString(for: oid)).")
        }

        return commitPointer
    }

    private func headCommit() throws -> OpaquePointer {
        let headReference = try currentBranchReference()
        defer { git_reference_free(headReference) }

        let headOID = try referenceTargetOID(for: headReference)
        return try lookupCommit(oid: headOID)
    }

    private func fullReferenceName(for reference: OpaquePointer) throws -> String {
        guard let namePointer = git_reference_name(reference) else {
            throw PullError(description: "Could not determine reference name.")
        }

        return String(cString: namePointer)
    }

    private func cleanupMergeState() throws {
        let result = git_repository_state_cleanup(repositoryPointer)
        try Self.throwIfGitError(result)
    }

    private func hexString(for oid: git_oid) -> String {
        var rawOID = oid
        var buffer = [Int8](repeating: 0, count: 41)
        git_oid_tostr(&buffer, buffer.count, &rawOID)
        return String(cString: buffer)
    }

    fileprivate static func throwIfGitError(_ code: Int32) throws {
        guard code < 0 else {
            return
        }

        if let errorPointer = git_error_last() {
            let message = errorPointer.pointee.message.map {
                String(cString: $0)
            } ?? "Unknown libgit2 error"

            throw PullError(description: message)
        }

        throw PullError(description: "libgit2 error code: \(code)")
    }
}

private struct MergeAnalysis {
    let analysis: git_merge_analysis_t
    let preference: git_merge_preference_t

    var isUpToDate: Bool {
        analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0
    }

    var isFastForward: Bool {
        analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0
    }
}
