//
//  ExecutionDetailView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

struct ExecutionDetailView: View {
    let file: Sync.ExecutionFileDetails
    let sync: Sync
    var onExecutionCompletionChanged: () -> Void = {}
    @State private var execution: Execution?
    @State private var saveTask: Task<Void, Never>?
    @State private var lastSavedCompletionState: Bool
    
    init(file: Sync.ExecutionFileDetails, sync: Sync, onExecutionCompletionChanged: @escaping () -> Void = {}) {
        self.file = file
        self.sync = sync
        self.onExecutionCompletionChanged = onExecutionCompletionChanged
        _execution = State(initialValue: file.execution)
        _lastSavedCompletionState = State(initialValue: file.execution.isCompleted)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if execution?.isCompleted == true {
                completedBanner
                    .padding()
                    .background(.bar)
                
                Divider()
            }
            
            ProgramView(
                execution: Binding(
                    get: { execution },
                    set: { newExecution in
                        execution = newExecution
                        
                        if let newExecution {
                            scheduleSave(newExecution)
                        }
                    }
                ),
                currentActor: { sync.gitCommitIdentity() },
                isReadOnly: execution?.isCompleted == true
            )
        }
        .navigationTitle(navigationTitle)
        .checklistdInlineNavigationTitle()
        .toolbar {
            if let execution {
                NavigationLink {
                    ExecutionHistoryView(execution: execution)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("History")
            }
        }
    }

    private var completedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("Execution complete")
                .font(.headline)
            Spacer()
        }
    }
    
    private var navigationTitle: String {
        guard let execution else { return "Execution" }
        let executionName = execution.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return executionName.isEmpty ? execution.program.title : executionName
    }
    
    private func scheduleSave(_ execution: Execution) {
        saveTask?.cancel()
        let fileURL = file.fileURL
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await sync.saveExecution(execution, to: fileURL)
            guard !Task.isCancelled else { return }
            if execution.isCompleted != lastSavedCompletionState {
                lastSavedCompletionState = execution.isCompleted
                onExecutionCompletionChanged()
            }
        }
    }
}
