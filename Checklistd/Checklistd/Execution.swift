//
//  Execution.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-13.
//

import Foundation

struct Execution {
    let id = UUID().uuidString
    let program: Program
    lazy var programCounter: String? = program.steps.first?.step.id
    
    var variables = [String: Variable]()
    var activeSteps: [ActiveStep] = []
    var isCompleted: Bool = false
    
    enum ExecutionError: Error {
        case stepNotFound
    }
    
    mutating func run() throws {
        while let currentProgramCounter = programCounter,
              let currentStep = activeSteps.last,
              currentStep.isCompleted,
              currentStep.stepEnvelope.step.id == currentProgramCounter {
            guard let nextStepId = currentStep.stepEnvelope.step.getNextStep() else {
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
        
        activeSteps = try activeSteps.map({ try $0.compute(with: variables)})
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
        activeSteps = try activeSteps.map({ try $0.compute(with: variables) })
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

struct ActiveStep {
    let stepEnvelope: StepEnvelope
    var computedStep: StepEnvelope
    var isCompleted: Bool = false
    
    init(stepEnvelope: StepEnvelope) {
        self.stepEnvelope = stepEnvelope
        self.computedStep = stepEnvelope
    }
    
    func compute(with variables: [String: Variable]) throws -> ActiveStep {
        var copy = self
        copy.computedStep = StepEnvelope(step: try stepEnvelope.step.compute(variables: variables))
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
