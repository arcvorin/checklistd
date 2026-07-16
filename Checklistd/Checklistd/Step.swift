//
//  Step.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import VersionedCodable
import Expression
enum StepType : String, Codable {
    case text
    case input
    case compute
    case conditional
    var metatype: Step.Type {
        switch self {
            case .text: return TextStep.self
            case .input: return InputStep.self
            case .compute: return ComputeStep.self
            case .conditional: return ConditionalStep.self
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
    var metadata: StepMetadata { get }
    func compute(variables: [String: Variable]) throws -> Step
    func canComplete(with variables: [String: Variable]) throws -> Bool
    func getNextStep() -> String?
}

struct StepMetadata: Codable {
    var id: String
    var name: String
    var description: String?
    var visible: Bool
    
    init(id: String, name: String = "Untitled", description: String? = nil, visible: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.visible = visible
    }
    
    private enum CodingKeys: CodingKey {
        case id, name, description, visible
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }
}

extension Step {
    var id: String {
        metadata.id
    }
    var name: String {
        metadata.name
    }
    
    var description: String? {
        metadata.description
    }
    
    func getNextStep() -> String? {
        nil
    }
    var visible: Bool {
        metadata.visible
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
    var metadata: StepMetadata
    var message: String
    private var nextStepId: String?
    
    init(id: String, message: String, nextStepId: String? = nil) {
        self.type = .text
        self.metadata = StepMetadata(id: id)
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
    var metadata: StepMetadata
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

indirect enum ConditionalExpression: Codable {
    case greaterThan(lhs: Float, rhs: Float, orEqual: Bool = false)
    case lessThan(lhs: Float, rhs: Float, orEqual: Bool = false)
    case numericEqual(lhs: Float, rhs: Float)
    case stringEqual(lhs: String, rhs: String)
    case dateEqual(lhs: Date, rhs: Date)
    case stringIn(lhs: String, rhs: [String])
    case dateIn(lhs: Date, rhs: [Date])
    case numericIn(lhs: Float, rhs: [Float])
    case and(expressions: [ConditionalExpression])
    case or(expressions: [ConditionalExpression])
    case negate(expression: ConditionalExpression)
    case boolean(value: Bool)
    case before(lhs: Date, rhs: Date, orEqual: Bool = false)
    case after(lhs: Date, rhs: Date, orEqual: Bool = false)
    case sameDay(lhs: Date, rhs: Date)
    
    func evaluate() -> Bool {
        switch self {
        case .boolean(value: let val):
            return val
        case .negate(expression: let expression):
            return !expression.evaluate()
        case .and(expressions: let expressions):
            return expressions.allSatisfy({$0.evaluate()})
        case .or(expressions: let expressions):
            return expressions.contains(where: { $0.evaluate()})
        }
    }
}

struct ConditionalStep: Step {
    var type = StepType.conditional
    var metadata: StepMetadata
    var condition: ConditionalExpression
    func compute(variables: [String : Variable]) throws -> any Step {
        self
    }
}

struct ComputeStep: Step {
    var type = StepType.compute
    var metadata: StepMetadata
    var key: String
    var expression: String
    var computedValue: Float?
    var nextStepId: String
    
    func expressionVariables() -> [String] {
        let expr = Expression(expression)
        var seenVariables = Set<String>()
        
        return expr.symbols.compactMap { symbol -> String? in
            guard case .variable(let name) = symbol else { return nil }
            guard !seenVariables.contains(name) else { return nil }
            seenVariables.insert(name)
            return name
        }
    }
    
    func missingOrNonNumericVariables(in availableVariables: [String: Variable]) -> [String] {
        expressionVariables().filter { variableName in
            guard let variable = availableVariables[variableName] else { return true }
            return variable.numericValue == nil
        }
    }
    
    func canEvaluate(variables: [String: Variable]) -> Bool {
        missingOrNonNumericVariables(in: variables).isEmpty
    }
    
    func compute(variables: [String: Variable]) throws -> any Step {
        var copy = self
        guard self.canEvaluate(variables: variables) else {
            throw ComputeError.variableStorageMismatch
        }
        
        let expressionVariables = expressionVariables()
        let constants = Dictionary(uniqueKeysWithValues: expressionVariables.map { variableName in
            (variableName, variables[variableName]!.numericValue!)
        })
        let expr = Expression(expression, constants: constants)
        
        copy.computedValue = Float(try expr.evaluate())
        return copy
    }
    
    func canComplete(with variables: [String : Variable]) throws -> Bool {
        canEvaluate(variables: variables)
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
