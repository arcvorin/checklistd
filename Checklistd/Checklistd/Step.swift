//
//  Step.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import VersionedCodable

enum StepType : String, Codable {
    case text
    case input
    var metatype: Step.Type {
        switch self {
            case .text: return TextStep.self
            case .input: return InputStep.self
        }
        
    }
}

enum InputKind : Codable {
    case text
    case int(start: Int?, end: Int?)
    case bool
    case float(start: Double?, end: Double?)
    case date(start: Date?, end: Date?, options: [Date]?)
    case choice(options: [String], allowOther: Bool)
    
    func storageMediumRepresentation() -> StorageMedium {
        switch self {
            case .text: return .string
            case .int: return .int
            case .bool: return .bool
            case .float: return .float
            case .date: return .date
            case .choice: return .string
        }
    }
    
    func validate(_ variable: Variable) throws {
        guard variable.storageMediumRepresentation() == storageMediumRepresentation() else {
            throw ComputeError.variableStorageMismatch
        }
        
        switch (self, variable) {
            case (.text, .string(let value)):
                guard !value.isEmpty else { throw ComputeError.missingRequiredInput }
            case (.int(let start, let end), .int(let value)):
                if let start, value < start { throw ComputeError.inputOutOfBounds }
                if let end, value > end { throw ComputeError.inputOutOfBounds }
            case (.float(let start, let end), .float(let value)):
                let doubleValue = Double(value)
                if let start, doubleValue < start { throw ComputeError.inputOutOfBounds }
                if let end, doubleValue > end { throw ComputeError.inputOutOfBounds }
            case (.date(let start, let end, let options), .date(let value)):
                if let start, value < start { throw ComputeError.inputOutOfBounds }
                if let end, value > end { throw ComputeError.inputOutOfBounds }
                if let options, !options.contains(value) { throw ComputeError.invalidOption }
            case (.choice(let options, let allowOther), .string(let value)):
                guard !value.isEmpty else { throw ComputeError.missingRequiredInput }
                if !allowOther && !options.contains(value) { throw ComputeError.invalidOption }
            case (.bool, .bool):
                break
            default:
                throw ComputeError.variableStorageMismatch
        }
    }
}



protocol Step : Codable {
    var type: StepType { get }
    var id: String { get }
    var name: String { get }
    var description: String? { get }
    var visible: Bool { get }
    func compute(variables: [String: Variable]) throws -> Step
    func canComplete(with variables: [String: Variable]) throws -> Bool
    func getNextStep() -> String?
}

extension Step {
    var id: String {
        UUID().uuidString
    }
    var name: String {
        "Untitled"
    }
    
    var description: String? {
        nil
    }
    
    func getNextStep() -> String? {
        nil
    }
    var visible: Bool {
        true
    }
    
    func canComplete(with variables: [String: Variable]) throws -> Bool {
        true
    }
    
}

enum ComputeError: Error {
    case variableStorageMismatch
    case missingRequiredInput
    case inputOutOfBounds
    case invalidOption
}

struct TextStep: Step {
    var type = StepType.text
    var id: String
    var message: String
    private var nextStepId: String?
    
    init(id: String, message: String, nextStepId: String? = nil) {
        self.type = .text
        self.id = id
        self.message = message
        self.nextStepId = nextStepId
    }
    
    func compute(variables: [String: Variable]) -> Step {
        var copy = self
        copy.message = (try? Parser.interpolate(message, variables: variables)) ?? message
        return copy
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
}

struct InputStep: Step {
    var type = StepType.input
    var id: String
    var inputKind: InputKind
    var label: String?
    var value: Variable?
    var key: String
    private var nextStepId: String
    
    func compute(variables: [String : Variable]) throws -> any Step {
        var copy = self
        copy.label = label != nil ? (try? Parser.interpolate(label!, variables: variables)) : nil
        if (variables.keys.contains(key)) {
            copy.value = variables[key]
        }
        guard let copyValue = copy.value else { return copy }
        try inputKind.validate(copyValue)
        return copy
    }
    
    func canComplete(with variables: [String: Variable]) throws -> Bool {
        let computedStep = try compute(variables: variables)
        guard let computedInputStep = computedStep as? InputStep else {
            return false
        }
        guard let value = computedInputStep.value else {
            throw ComputeError.missingRequiredInput
        }
        try inputKind.validate(value)
        return true
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
}

struct StepEnvelope {
    let step: Step
}

extension StepEnvelope: Codable {
    
    private enum CodingKeys: CodingKey {
        case type, step
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        self.step = try type.metatype.init(from: container.superDecoder(forKey: .step))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step.type, forKey: .type)
        try step.encode(to: container.superEncoder(forKey: .step))
    }
}
