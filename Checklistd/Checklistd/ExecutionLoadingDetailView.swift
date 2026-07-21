//
//  ExecutionLoadingDetailView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-20.
//
import SwiftUI

struct ExecutionLoadingDetailView: View {
    let fileURL: URL
    let cachedFile: Sync.ExecutionFileDetails?
    let sync: Sync
    var onExecutionCompletionChanged: () -> Void = {}
    @State private var file: Sync.ExecutionFileDetails?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let file {
                if file.execution.isCompleted {
                    ExecutionHistoryView(execution: file.execution)
                } else {
                    ExecutionDetailView(file: file, sync: sync, onExecutionCompletionChanged: onExecutionCompletionChanged)
                }
            } else if let errorMessage {
                ContentUnavailableView("Execution not found", systemImage: "doc.badge.questionmark", description: Text(errorMessage))
            } else {
                LoadingExecutionView(message: "Loading execution...")
            }
        }
        .task(id: fileURL) {
            await loadExecution()
        }
    }
    
    private func loadExecution() async {
        file = nil
        errorMessage = nil
        
        await sync.pullRepos()
        
        if let loadedFile = await sync.loadExecutionFileDetails(for: fileURL) {
            file = loadedFile
        } else if let cachedFile {
            file = cachedFile
        } else {
            errorMessage = fileURL.lastPathComponent
        }
    }
}
