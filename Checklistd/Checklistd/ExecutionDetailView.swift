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
    @State private var execution: Execution?
    @State private var saveTask: Task<Void, Never>?
    
    init(file: Sync.ExecutionFileDetails, sync: Sync) {
        self.file = file
        self.sync = sync
        _execution = State(initialValue: file.execution)
    }
    
    var body: some View {
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
            currentActor: { sync.gitCommitIdentity() }
        )
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
        .onDisappear {
            saveTask?.cancel()
            if let execution {
                Task {
                    await sync.saveExecution(execution, to: file.fileURL)
                }
            }
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
        }
    }
}
