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
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    
    init(execution: Execution) {
        self.execution = execution
        _selectedIndex = State(initialValue: 0)
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
        .onDisappear {
            stopPlayback()
        }
    }
    
    private var historyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last updated \(Self.timestampFormatter.string(from: execution.updatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Button {
                    stopPlayback()
                    moveToBeginning()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveBackward)
                
                Button {
                    stopPlayback()
                    selectedIndex = max(selectedIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveBackward)
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(execution.history.isEmpty || (!isPlaying && !canMoveForward))
                
                Text(positionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80)
                
                Button {
                    stopPlayback()
                    moveForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveForward)
                
                Button {
                    stopPlayback()
                    moveToEnd()
                } label: {
                    Image(systemName: "forward.end.fill")
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

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard canMoveForward else { return }
        playbackTask?.cancel()
        isPlaying = true
        playbackTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    break
                }
                
                guard canMoveForward else {
                    stopPlayback()
                    break
                }
                
                moveForward()
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func moveForward() {
        selectedIndex = min(selectedIndex + 1, execution.history.count - 1)
        if !canMoveForward {
            stopPlayback()
        }
    }

    private func moveToBeginning() {
        selectedIndex = 0
    }

    private func moveToEnd() {
        guard !execution.history.isEmpty else { return }
        selectedIndex = execution.history.count - 1
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
        if let stepReference = event.displayStepReference {
            return "\(event.displayTitle): \(stepReference)"
        }
        return event.displayTitle
    }
    
    private func eventSubtitle(for event: ExecutionHistoryEvent) -> String {
        "\(event.actorName) <\(event.actorEmail)> at \(event.timestamp.formatted(date: .abbreviated, time: .standard))"
    }
    
    private func eventPayload(for event: ExecutionHistoryEvent) -> String? {
        let lines = [event.displaySentence] + event.displayPayloadLines
        return lines.joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
