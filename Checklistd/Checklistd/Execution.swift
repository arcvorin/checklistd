//
//  Execution.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-13.
//

import Foundation

struct Execution: Codable {
    let id: String
    let program: Program
    var programCounter: String?
    
    var variables = [String: Variable]()
    var activeSteps: [ActiveStep] = []
    var isCompleted: Bool = false
    
    init(
        id: String = UUID().uuidString,
        program: Program,
        programCounter: String? = nil,
        variables: [String: Variable] = [:],
        activeSteps: [ActiveStep] = [],
        isCompleted: Bool = false
    ) {
        self.id = id
        self.program = program
        self.programCounter = programCounter ?? program.steps.first?.step.id
        self.variables = variables
        self.activeSteps = activeSteps
        self.isCompleted = isCompleted
    }
    
    enum ExecutionError: Error {
        case stepNotFound
    }
    
    mutating func run() throws {
        while let currentProgramCounter = programCounter,
              let currentStep = activeSteps.last,
              currentStep.isCompleted,
              currentStep.stepEnvelope.step.id == currentProgramCounter {
            guard let nextStepId = currentStep.computedStep.step.getNextStep() else {
                isCompleted = true
                return
            }
            programCounter = nextStepId
        }
        
        guard let programCounter else {
            isCompleted = true
            return
        }
        
        guard let programCounterStepEnvelope = program.steps.first(where: { $0.step.id == programCounter }) else {
            throw ExecutionError.stepNotFound
        }
        
        if (activeSteps.first(where: { $0.stepEnvelope.step.id == programCounter && !$0.isCompleted }) == nil) {
            activeSteps.append(ActiveStep(stepEnvelope: programCounterStepEnvelope))
        }
        
        activeSteps = try activeSteps.enumerated().map { index, activeStep in
            try activeStep.compute(
                with: variables,
                updateInputValueFromVariables: index == activeSteps.index(before: activeSteps.endIndex)
            )
        }
        updateVariablesFromComputedSteps()
        
        if let currentStep = activeSteps.last, !currentStep.computedStep.step.visible {
            activeSteps.removeLast()
            activeSteps.append(try currentStep.withCompletion(true, variables: variables))
            try self.run()
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
    
    mutating func completeStep() throws {
        guard var currentStep = activeSteps.last else {
            isCompleted = true
            return
        }
        
        currentStep = try currentStep.withCompletion(true, variables: variables)
        if let inputStep = currentStep.computedStep.step as? InputStep,
           let value = inputStep.value {
            variables[inputStep.key] = value
        }
        activeSteps.removeLast()
        activeSteps.append(currentStep)
        try self.run()
    }
    
    mutating func reopenStep(at index: Int) throws {
        guard activeSteps.indices.contains(index) else {
            throw ExecutionError.stepNotFound
        }
        
        let removedSteps = activeSteps.suffix(from: activeSteps.index(after: index))
        for activeStep in removedSteps {
            if let inputStep = activeStep.stepEnvelope.step as? InputStep {
                variables.removeValue(forKey: inputStep.key)
            }
            if let computeStep = activeStep.stepEnvelope.step as? ComputeStep {
                variables.removeValue(forKey: computeStep.key)
            }
        }
        
        activeSteps.removeSubrange(activeSteps.index(after: index)..<activeSteps.endIndex)
        activeSteps[index] = try activeSteps[index].withCompletion(false, variables: variables)
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
    
    mutating func setVariable(name: String, value: Variable) throws {
        variables[name] = value
        try self.run()
    }
    
    mutating func clearVariable(name: String) throws {
        variables.removeValue(forKey: name)
        try self.run()
    }
    //var history: [ExecutionAction] = []
    
}

struct ActiveStep: Codable {
    let stepEnvelope: StepEnvelope
    var computedStep: StepEnvelope
    var isCompleted: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case stepEnvelope
        case computedStep
        case isCompleted
    }
    
    init(stepEnvelope: StepEnvelope) {
        self.stepEnvelope = stepEnvelope
        self.computedStep = stepEnvelope
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
}
