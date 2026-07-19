//
//  Execution.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-13.
//

import Foundation

struct Execution: Codable {
    let id: String
    var name: String
    let createdByName: String
    let createdByEmail: String
    let createdAt: Date
    var updatedAt: Date
    let program: Program
    var programCounter: String?
    
    var variables = [String: Variable]()
    var activeSteps: [ActiveStep] = []
    var history: [ExecutionHistoryEvent] = []
    var isCompleted: Bool = false
    
    init(
        id: String = UUID().uuidString,
        name: String = "",
        createdByName: String = "",
        createdByEmail: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        program: Program,
        programCounter: String? = nil,
        variables: [String: Variable] = [:],
        activeSteps: [ActiveStep] = [],
        history: [ExecutionHistoryEvent] = [],
        isCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdByName = createdByName
        self.createdByEmail = createdByEmail
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.program = program
        self.programCounter = programCounter ?? program.steps.first?.step.id
        self.variables = variables
        self.activeSteps = activeSteps
        self.history = history
        self.isCompleted = isCompleted
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdByName
        case createdByEmail
        case createdAt
        case updatedAt
        case program
        case programCounter
        case variables
        case activeSteps
        case history
        case isCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.createdByName = try container.decode(String.self, forKey: .createdByName)
        self.createdByEmail = try container.decode(String.self, forKey: .createdByEmail)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.program = try container.decode(Program.self, forKey: .program)
        self.programCounter = try container.decodeIfPresent(String.self, forKey: .programCounter)
        self.variables = try container.decodeIfPresent([String: Variable].self, forKey: .variables) ?? [:]
        self.activeSteps = try container.decodeIfPresent([ActiveStep].self, forKey: .activeSteps) ?? []
        self.history = try container.decode([ExecutionHistoryEvent].self, forKey: .history)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdByName, forKey: .createdByName)
        try container.encode(createdByEmail, forKey: .createdByEmail)
        try container.encode(ExecutionTimestampFormatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(ExecutionTimestampFormatter.string(from: updatedAt), forKey: .updatedAt)
        try container.encode(program, forKey: .program)
        try container.encodeIfPresent(programCounter, forKey: .programCounter)
        try container.encode(variables, forKey: .variables)
        try container.encode(activeSteps, forKey: .activeSteps)
        try container.encode(history, forKey: .history)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
    
    enum ExecutionError: Error {
        case stepNotFound
    }
    
    mutating func recordCreation(actor: GitCommitIdentity) {
        appendHistoryEvent(.executionCreated, actor: actor)
    }
    
    mutating func run(actor: GitCommitIdentity? = nil) throws {
        while let currentProgramCounter = programCounter,
              let currentStep = activeSteps.last,
              currentStep.isCompleted,
              currentStep.stepEnvelope.step.id == currentProgramCounter {
            guard let nextStepId = currentStep.computedStep.step.getNextStep() else {
                isCompleted = true
                appendHistoryEvent(.executionCompleted, actor: actor)
                return
            }
            programCounter = nextStepId
        }
        
        guard let programCounter else {
            isCompleted = true
            appendHistoryEvent(.executionCompleted, actor: actor)
            return
        }
        
        guard let programCounterStepEnvelope = program.steps.first(where: { $0.step.id == programCounter }) else {
            throw ExecutionError.stepNotFound
        }
        
        if (activeSteps.first(where: { $0.stepEnvelope.step.id == programCounter && !$0.isCompleted }) == nil) {
            activeSteps.append(ActiveStep(stepEnvelope: programCounterStepEnvelope, actor: actor))
            appendHistoryEvent(.stepActivated, actor: actor, step: programCounterStepEnvelope.step)
        }
        
        activeSteps = try activeSteps.enumerated().map { index, activeStep in
            try activeStep.compute(
                with: variables,
                updateInputValueFromVariables: index == activeSteps.index(before: activeSteps.endIndex)
            )
        }
        updateVariablesFromComputedSteps()
        
        if let currentStep = activeSteps.last,
           currentStep.stepEnvelope.step.id == programCounter {
            appendDerivedEvent(for: currentStep.computedStep.step, actor: actor)
        }
        
        if let currentStep = activeSteps.last, !currentStep.computedStep.step.visible {
            activeSteps.removeLast()
            activeSteps.append(try currentStep.withCompletion(true, variables: variables))
            try self.run(actor: actor)
        }
    }
    
    mutating private func updateVariablesFromComputedSteps() {
        for activeStep in activeSteps {
            guard let computeStep = activeStep.computedStep.step as? ComputeStep,
                  let computedValue = computeStep.computedValue else {
                continue
            }
            variables[computeStep.key] = .float(float: computedValue)
        }
    }
    
    mutating func completeStep(actor: GitCommitIdentity? = nil) throws {
        guard var currentStep = activeSteps.last else {
            isCompleted = true
            appendHistoryEvent(.executionCompleted, actor: actor)
            return
        }
        
        currentStep = currentStep.withActor(actor)
        currentStep = try currentStep.withCompletion(true, variables: variables)
        appendHistoryEvent(.stepCompleted, actor: actor, step: currentStep.computedStep.step)
        if let inputStep = currentStep.computedStep.step as? InputStep,
           let value = inputStep.value {
            variables[inputStep.key] = value
        }
        activeSteps.removeLast()
        activeSteps.append(currentStep)
        try self.run(actor: actor)
    }
    
    mutating func reopenStep(at index: Int, actor: GitCommitIdentity? = nil) throws {
        guard activeSteps.indices.contains(index) else {
            throw ExecutionError.stepNotFound
        }
        
        let removedSteps = activeSteps.suffix(from: activeSteps.index(after: index))
        let removedStepIds = removedSteps.map(\.stepEnvelope.step.id)
        for activeStep in removedSteps {
            if let inputStep = activeStep.stepEnvelope.step as? InputStep {
                variables.removeValue(forKey: inputStep.key)
            }
            if let computeStep = activeStep.stepEnvelope.step as? ComputeStep {
                variables.removeValue(forKey: computeStep.key)
            }
        }
        appendHistoryEvent(
            .stepReopened,
            actor: actor,
            step: activeSteps[index].computedStep.step,
            reopenedIndex: index,
            removedStepIds: Array(removedStepIds)
        )
        
        activeSteps.removeSubrange(activeSteps.index(after: index)..<activeSteps.endIndex)
        activeSteps[index] = try activeSteps[index]
            .withActor(actor)
            .withCompletion(false, variables: variables)
        programCounter = activeSteps[index].stepEnvelope.step.id
        isCompleted = false
        activeSteps = try activeSteps.enumerated().map { index, activeStep in
            try activeStep.compute(
                with: variables,
                updateInputValueFromVariables: index == activeSteps.index(before: activeSteps.endIndex)
            )
        }
    }
    
    mutating func setVariable(name: String, value: String) throws {
        try setVariable(name: name, value: .string(value: value))
    }
    
    mutating func setVariable(
        name: String,
        value: Variable,
        actor: GitCommitIdentity? = nil,
        inputStep: InputStep? = nil
    ) throws {
        let previousValue = variables[name]
        variables[name] = value
        updateActiveStepActor(stepId: inputStep?.id, actor: actor)
        appendInputChangedEvent(
            key: name,
            value: value,
            previousValue: previousValue,
            actor: actor,
            inputStep: inputStep
        )
        try self.run(actor: actor)
    }
    
    mutating func clearVariable(
        name: String,
        actor: GitCommitIdentity? = nil,
        inputStep: InputStep? = nil
    ) throws {
        let previousValue = variables[name]
        variables.removeValue(forKey: name)
        updateActiveStepActor(stepId: inputStep?.id, actor: actor)
        appendHistoryEvent(
            .inputCleared,
            actor: actor,
            step: inputStep,
            key: name,
            previousValue: previousValue
        )
        try self.run(actor: actor)
    }
    
}

extension Execution {
    func markdownAudit() -> String {
        var lines: [String] = [
            "# \(markdownValue(executionTitle))",
            "",
            "- Execution ID: \(id)",
            "- Program: \(markdownValue(program.title))",
            "- Created: \(ExecutionTimestampFormatter.string(from: createdAt))",
            "- Updated: \(ExecutionTimestampFormatter.string(from: updatedAt))",
            "- Created by: \(markdownActor(name: createdByName, email: createdByEmail))",
            "",
            "## Events"
        ]
        
        if history.isEmpty {
            lines.append("")
            lines.append("No recorded events.")
        } else {
            lines.append(contentsOf: history.map(markdownLine(for:)))
        }
        
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    private var executionTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? program.title : "\(trimmedName) (\(program.title))"
    }
    
    private mutating func appendDerivedEvent(for step: Step, actor: GitCommitIdentity?) {
        if let computeStep = step as? ComputeStep,
           let computedValue = computeStep.computedValue {
            appendHistoryEvent(
                .stepComputed,
                actor: actor,
                step: computeStep,
                key: computeStep.key,
                value: .float(float: computedValue),
                nextStepId: computeStep.getNextStep()
            )
        } else if let conditionalStep = step as? ConditionalStep,
                  let result = conditionalStep.result {
            appendHistoryEvent(
                .conditionEvaluated,
                actor: actor,
                step: conditionalStep,
                result: result,
                nextStepId: conditionalStep.getNextStep()
            )
        }
    }
    
    private mutating func updateActiveStepActor(stepId: String?, actor: GitCommitIdentity?) {
        guard let stepId, let actor else { return }
        guard let index = activeSteps.indices.last(where: { activeSteps[$0].stepEnvelope.step.id == stepId }) else { return }
        activeSteps[index] = activeSteps[index].withActor(actor)
    }
    
    private mutating func appendInputChangedEvent(
        key: String,
        value: Variable,
        previousValue: Variable?,
        actor: GitCommitIdentity?,
        inputStep: InputStep?
    ) {
        guard let actor else { return }
        let shouldCoalesce = inputStep?.inputKind.isFreeTextTyping == true
        if shouldCoalesce,
           let lastIndex = history.indices.last,
           history[lastIndex].type == .inputChanged,
           history[lastIndex].key == key,
           history[lastIndex].stepId == inputStep?.id,
           history[lastIndex].actorName == actor.name,
           history[lastIndex].actorEmail == actor.email,
           history[lastIndex].coalescesTyping {
            history[lastIndex].timestamp = Date()
            history[lastIndex].value = value
            return
        }
        
        appendHistoryEvent(
            .inputChanged,
            actor: actor,
            step: inputStep,
            key: key,
            value: value,
            previousValue: previousValue,
            coalescesTyping: shouldCoalesce
        )
    }
    
    private mutating func appendHistoryEvent(
        _ type: ExecutionHistoryEvent.EventType,
        actor: GitCommitIdentity?,
        step: Step? = nil,
        key: String? = nil,
        value: Variable? = nil,
        previousValue: Variable? = nil,
        result: Bool? = nil,
        nextStepId: String? = nil,
        reopenedIndex: Int? = nil,
        removedStepIds: [String]? = nil,
        coalescesTyping: Bool = false
    ) {
        guard let actor else { return }
        history.append(
            ExecutionHistoryEvent(
                type: type,
                actorName: actor.name,
                actorEmail: actor.email,
                stepId: step?.id,
                stepName: step?.name,
                stepLabel: Self.stepLabel(for: step),
                key: key,
                value: value,
                previousValue: previousValue,
                result: result,
                nextStepId: nextStepId,
                reopenedIndex: reopenedIndex,
                removedStepIds: removedStepIds,
                coalescesTyping: coalescesTyping
            )
        )
    }
    
    private static func stepLabel(for step: Step?) -> String? {
        if let inputStep = step as? InputStep {
            return inputStep.label
        }
        if let textStep = step as? TextStep {
            return textStep.message
        }
        return nil
    }
    
    private func markdownLine(for event: ExecutionHistoryEvent) -> String {
        var parts = [
            "- \(ExecutionTimestampFormatter.string(from: event.timestamp))",
            "**\(event.type.rawValue)**",
            markdownActor(name: event.actorName, email: event.actorEmail)
        ]
        
        if let stepDescription = markdownStepDescription(for: event) {
            parts.append(stepDescription)
        }
        
        let payload = markdownPayload(for: event)
        if !payload.isEmpty {
            parts.append(payload)
        }
        
        return parts.joined(separator: " - ")
    }
    
    private func markdownStepDescription(for event: ExecutionHistoryEvent) -> String? {
        let displayName = event.stepLabel ?? event.stepName ?? event.stepId
        guard let displayName else { return nil }
        
        if let stepId = event.stepId {
            return "\(markdownValue(displayName)) (`\(stepId)`)"
        }
        
        return markdownValue(displayName)
    }
    
    private func markdownPayload(for event: ExecutionHistoryEvent) -> String {
        var payload: [String] = []
        
        if let key = event.key {
            payload.append("key `\(key)`")
        }
        if let previousValue = event.previousValue {
            payload.append("previous `\(previousValue.interpolatedValue)`")
        }
        if let value = event.value {
            payload.append("value `\(value.interpolatedValue)`")
        }
        if let result = event.result {
            payload.append("result `\(result)`")
        }
        if let nextStepId = event.nextStepId {
            payload.append("next `\(nextStepId)`")
        }
        if let reopenedIndex = event.reopenedIndex {
            payload.append("reopened index `\(reopenedIndex)`")
        }
        if let removedStepIds = event.removedStepIds, !removedStepIds.isEmpty {
            payload.append("removed `\(removedStepIds.joined(separator: ", "))`")
        }
        
        return payload.joined(separator: ", ")
    }
    
    private func markdownActor(name: String, email: String) -> String {
        "\(markdownValue(name)) <\(email)>"
    }
    
    private func markdownValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }
}

extension InputKind {
    var isFreeTextTyping: Bool {
        if case .text = self {
            return true
        }
        return false
    }
}

struct ExecutionHistoryEvent: Codable, Identifiable {
    enum EventType: String, Codable {
        case executionCreated
        case inputChanged
        case inputCleared
        case stepCompleted
        case stepReopened
        case stepActivated
        case stepComputed
        case conditionEvaluated
        case executionCompleted
    }
    
    var id: String
    var timestamp: Date
    var actorName: String
    var actorEmail: String
    var type: EventType
    var stepId: String?
    var stepName: String?
    var stepLabel: String?
    var key: String?
    var value: Variable?
    var previousValue: Variable?
    var result: Bool?
    var nextStepId: String?
    var reopenedIndex: Int?
    var removedStepIds: [String]?
    var coalescesTyping: Bool
    
    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: EventType,
        actorName: String,
        actorEmail: String,
        stepId: String? = nil,
        stepName: String? = nil,
        stepLabel: String? = nil,
        key: String? = nil,
        value: Variable? = nil,
        previousValue: Variable? = nil,
        result: Bool? = nil,
        nextStepId: String? = nil,
        reopenedIndex: Int? = nil,
        removedStepIds: [String]? = nil,
        coalescesTyping: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.actorName = actorName
        self.actorEmail = actorEmail
        self.stepId = stepId
        self.stepName = stepName
        self.stepLabel = stepLabel
        self.key = key
        self.value = value
        self.previousValue = previousValue
        self.result = result
        self.nextStepId = nextStepId
        self.reopenedIndex = reopenedIndex
        self.removedStepIds = removedStepIds
        self.coalescesTyping = coalescesTyping
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case actorName
        case actorEmail
        case type
        case stepId
        case stepName
        case stepLabel
        case key
        case value
        case previousValue
        case result
        case nextStepId
        case reopenedIndex
        case removedStepIds
        case coalescesTyping
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ExecutionTimestampFormatter.string(from: timestamp), forKey: .timestamp)
        try container.encode(actorName, forKey: .actorName)
        try container.encode(actorEmail, forKey: .actorEmail)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(stepId, forKey: .stepId)
        try container.encodeIfPresent(stepName, forKey: .stepName)
        try container.encodeIfPresent(stepLabel, forKey: .stepLabel)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(previousValue, forKey: .previousValue)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(nextStepId, forKey: .nextStepId)
        try container.encodeIfPresent(reopenedIndex, forKey: .reopenedIndex)
        try container.encodeIfPresent(removedStepIds, forKey: .removedStepIds)
        try container.encode(coalescesTyping, forKey: .coalescesTyping)
    }
}

private enum ExecutionTimestampFormatter {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
    
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct ActiveStep: Codable {
    let stepEnvelope: StepEnvelope
    var computedStep: StepEnvelope
    var actorName: String
    var actorEmail: String
    var isCompleted: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case stepEnvelope
        case computedStep
        case actorName
        case actorEmail
        case isCompleted
    }
    
    init(stepEnvelope: StepEnvelope, actor: GitCommitIdentity? = nil) {
        self.stepEnvelope = stepEnvelope
        self.computedStep = stepEnvelope
        self.actorName = actor?.name ?? ""
        self.actorEmail = actor?.email ?? ""
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stepEnvelope = try StepEnvelope(
            from: container.superDecoder(forKey: .stepEnvelope),
            mode: .program
        )
        self.computedStep = try StepEnvelope(
            from: container.superDecoder(forKey: .computedStep),
            mode: .execution
        )
        self.actorName = try container.decode(String.self, forKey: .actorName)
        self.actorEmail = try container.decode(String.self, forKey: .actorEmail)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try stepEnvelope.encode(
            to: container.superEncoder(forKey: .stepEnvelope),
            mode: .program
        )
        try computedStep.encode(
            to: container.superEncoder(forKey: .computedStep),
            mode: .execution
        )
        try container.encode(actorName, forKey: .actorName)
        try container.encode(actorEmail, forKey: .actorEmail)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
    
    func compute(with variables: [String: Variable], updateInputValueFromVariables: Bool) throws -> ActiveStep {
        var copy = self
        copy.computedStep = StepEnvelope(step: try stepEnvelope.step.compute(variables: variables))
        
        if !updateInputValueFromVariables,
           var inputStep = copy.computedStep.step as? InputStep,
           let previousInputStep = computedStep.step as? InputStep {
            inputStep.value = previousInputStep.value
            copy.computedStep = StepEnvelope(step: inputStep)
        }
        
        return copy
    }
    
    func withCompletion(_ isCompleted: Bool, variables: [String: Variable]) throws -> ActiveStep {
        if isCompleted {
            _ = try computedStep.step.canComplete(with: variables)
        }
        
        var copy = self
        copy.isCompleted = isCompleted
        return copy
    }
    
    func withActor(_ actor: GitCommitIdentity?) -> ActiveStep {
        guard let actor else { return self }
        
        var copy = self
        copy.actorName = actor.name
        copy.actorEmail = actor.email
        return copy
    }
}
