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
                        Task {
                            await sync.saveExecution(newExecution, to: file.fileURL)
                        }
                    }
                }
            )
        )
        .navigationTitle(execution?.program.title ?? "Execution")
        .checklistdInlineNavigationTitle()
    }
}
