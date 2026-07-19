//
//  ExecutionHistoryView.swift
//  Checklistd
//
//  Created by Codex on 2026-07-19.
//

import SwiftUI

struct ExecutionHistoryView: View {
    let execution: Execution
    @State private var selectedIndex: Int
    
    init(execution: Execution) {
        self.execution = execution
        _selectedIndex = State(initialValue: max(execution.history.count - 1, 0))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            historyControls
                .padding()
                .background(.bar)
            
            Divider()
            
            ProgramView(
                execution: .constant(replayedExecution),
                isReadOnly: true,
                stepHistoryEvents: stepHistoryEvents
            )
        }
        .navigationTitle("History")
        .checklistdInlineNavigationTitle()
    }
    
    private var historyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    selectedIndex = max(selectedIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveBackward)
                
                Text(positionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80)
                
                Button {
                    selectedIndex = min(selectedIndex + 1, execution.history.count - 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveForward)
                
                Spacer()
            }
            
            if let event = selectedEvent {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventTitle(for: event))
                        .font(.headline)
                    Text(eventSubtitle(for: event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let payload = eventPayload(for: event), !payload.isEmpty {
                        Text(payload)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No recorded history")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var selectedEvent: ExecutionHistoryEvent? {
        guard execution.history.indices.contains(selectedIndex) else { return nil }
        return execution.history[selectedIndex]
    }
    
    private var canMoveBackward: Bool {
        selectedIndex > 0 && !execution.history.isEmpty
    }
    
    private var canMoveForward: Bool {
        selectedIndex < execution.history.count - 1
    }
    
    private var positionText: String {
        guard !execution.history.isEmpty else { return "0 / 0" }
        return "\(selectedIndex + 1) / \(execution.history.count)"
    }
    
    private var replayedExecution: Execution? {
        guard !execution.history.isEmpty else { return execution }
        
        var replay = Execution(
            id: execution.id,
            name: execution.name,
            createdByName: execution.createdByName,
            createdByEmail: execution.createdByEmail,
            createdAt: execution.createdAt,
            updatedAt: selectedEvent?.timestamp ?? execution.updatedAt,
            program: execution.program
        )
        
        var hasStarted = false
        for event in execution.history.prefix(selectedIndex + 1) {
            do {
                if !hasStarted && event.type != .executionCreated {
                    try replay.run(actor: actor(for: event))
                    hasStarted = true
                }
                
                switch event.type {
                case .executionCreated:
                    replay.recordCreation(actor: actor(for: event))
                    try replay.run(actor: actor(for: event))
                    hasStarted = true
                case .inputChanged:
                    guard let key = event.key, let value = event.value else { break }
                    try replay.setVariable(
                        name: key,
                        value: value,
                        actor: actor(for: event),
                        inputStep: inputStep(for: event)
                    )
                case .inputCleared:
                    guard let key = event.key else { break }
                    try replay.clearVariable(
                        name: key,
                        actor: actor(for: event),
                        inputStep: inputStep(for: event)
                    )
                case .stepCompleted:
                    try replay.completeStep(actor: actor(for: event))
                case .stepReopened:
                    if let reopenedIndex = event.reopenedIndex {
                        try replay.reopenStep(at: reopenedIndex, actor: actor(for: event))
                    }
                case .stepActivated, .stepComputed, .conditionEvaluated, .executionCompleted:
                    break
                }
            } catch {
                print("Couldn't replay history event \(event.id): \(error)")
            }
        }
        
        replay.history = Array(execution.history.prefix(selectedIndex + 1))
        return replay
    }
    
    private var stepHistoryEvents: [String: ExecutionHistoryEvent] {
        guard !execution.history.isEmpty else { return [:] }
        return execution.history
            .prefix(selectedIndex + 1)
            .reduce(into: [String: ExecutionHistoryEvent]()) { result, event in
                guard let stepId = event.stepId else { return }
                result[stepId] = event
            }
    }
    
    private func actor(for event: ExecutionHistoryEvent) -> GitCommitIdentity {
        GitCommitIdentity(name: event.actorName, email: event.actorEmail)
    }
    
    private func inputStep(for event: ExecutionHistoryEvent) -> InputStep? {
        execution.program.steps
            .compactMap { $0.step as? InputStep }
            .first { inputStep in
                inputStep.id == event.stepId || inputStep.key == event.key
            }
    }
    
    private func eventTitle(for event: ExecutionHistoryEvent) -> String {
        if let stepLabel = event.stepLabel ?? event.stepName {
            return "\(event.type.rawValue): \(stepLabel)"
        }
        return event.type.rawValue
    }
    
    private func eventSubtitle(for event: ExecutionHistoryEvent) -> String {
        "\(event.actorName) <\(event.actorEmail)> at \(event.timestamp.formatted(date: .abbreviated, time: .standard))"
    }
    
    private func eventPayload(for event: ExecutionHistoryEvent) -> String? {
        var parts: [String] = []
        
        if let key = event.key {
            parts.append("key \(key)")
        }
        if let previousValue = event.previousValue {
            parts.append("previous \(previousValue.interpolatedValue)")
        }
        if let value = event.value {
            parts.append("value \(value.interpolatedValue)")
        }
        if let result = event.result {
            parts.append("result \(result)")
        }
        if let nextStepId = event.nextStepId {
            parts.append("next \(nextStepId)")
        }
        if let removedStepIds = event.removedStepIds, !removedStepIds.isEmpty {
            parts.append("removed \(removedStepIds.joined(separator: ", "))")
        }
        
        return parts.joined(separator: ", ")
    }
}
