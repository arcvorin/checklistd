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
    case int(start: Int?, end: Int?, options: [Int]?)
    case bool
    case float(start: Double?, end: Double?, options: [Float]?)
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
            case (.int(let start, let end, let options), .int(let value)):
                if let start, value < start { throw ComputeError.inputOutOfBounds }
                if let end, value > end { throw ComputeError.inputOutOfBounds }
                if let options, !options.contains(value) { throw ComputeError.invalidOption }
            case (.float(let start, let end, let options), .float(let value)):
                let doubleValue = Double(value)
                if let start, doubleValue < start { throw ComputeError.inputOutOfBounds }
                if let end, doubleValue > end { throw ComputeError.inputOutOfBounds }
                if let options, !options.contains(value) { throw ComputeError.invalidOption }
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

extension InputKind {
    private enum CodingKeys: String, CodingKey {
        case type
        case start
        case end
        case options
        case allowOther
    }
    
    private struct TypedOptions<Value: Codable>: Codable {
        var type: StorageMedium
        var values: [Value]
    }
    
    private enum KindType: String, Codable {
        case text
        case int
        case bool
        case float
        case date
        case choice
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        
        switch type {
        case .text:
            self = .text
        case .int:
            self = .int(
                start: try container.decodeIfPresent(Int.self, forKey: .start),
                end: try container.decodeIfPresent(Int.self, forKey: .end),
                options: try Self.decodeOptions(Int.self, expectedType: .int, from: container)
            )
        case .bool:
            self = .bool
        case .float:
            self = .float(
                start: try container.decodeIfPresent(Double.self, forKey: .start),
                end: try container.decodeIfPresent(Double.self, forKey: .end),
                options: try Self.decodeOptions(Float.self, expectedType: .float, from: container)
            )
        case .date:
            self = .date(
                start: try container.decodeIfPresent(Date.self, forKey: .start),
                end: try container.decodeIfPresent(Date.self, forKey: .end),
                options: try Self.decodeOptions(Date.self, expectedType: .date, from: container)
            )
        case .choice:
            self = .choice(
                options: try Self.decodeOptions(String.self, expectedType: .string, from: container) ?? [],
                allowOther: try container.decodeIfPresent(Bool.self, forKey: .allowOther) ?? false
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text:
            try container.encode(KindType.text, forKey: .type)
        case .int(let start, let end, let options):
            try container.encode(KindType.int, forKey: .type)
            try container.encodeIfPresent(start, forKey: .start)
            try container.encodeIfPresent(end, forKey: .end)
            try encodeOptions(options, type: .int, to: &container)
        case .bool:
            try container.encode(KindType.bool, forKey: .type)
        case .float(let start, let end, let options):
            try container.encode(KindType.float, forKey: .type)
            try container.encodeIfPresent(start, forKey: .start)
            try container.encodeIfPresent(end, forKey: .end)
            try encodeOptions(options, type: .float, to: &container)
        case .date(let start, let end, let options):
            try container.encode(KindType.date, forKey: .type)
            try container.encodeIfPresent(start, forKey: .start)
            try container.encodeIfPresent(end, forKey: .end)
            try encodeOptions(options, type: .date, to: &container)
        case .choice(let options, let allowOther):
            try container.encode(KindType.choice, forKey: .type)
            try encodeOptions(options, type: .string, to: &container)
            try container.encode(allowOther, forKey: .allowOther)
        }
    }
    
    private static func decodeOptions<Value: Codable>(
        _ valueType: Value.Type,
        expectedType: StorageMedium,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [Value]? {
        guard container.contains(.options) else { return nil }
        let options = try container.decode(TypedOptions<Value>.self, forKey: .options)
        guard options.type == expectedType else {
            throw DecodingError.dataCorruptedError(
                forKey: .options,
                in: container,
                debugDescription: "Expected \(expectedType.rawValue) options, got \(options.type.rawValue)."
            )
        }
        return options.values
    }
    
    private func encodeOptions<Value: Codable>(
        _ values: [Value]?,
        type: StorageMedium,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encodeIfPresent(values.map { TypedOptions(type: type, values: $0) }, forKey: .options)
    }
    
    func decodeVariable<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Variable? {
        guard container.contains(key) else { return nil }
        
        switch self {
        case .text, .choice:
            return .string(value: try container.decode(String.self, forKey: key))
        case .int:
            return .int(int: try container.decode(Int.self, forKey: key))
        case .bool:
            return .bool(bool: try container.decode(Bool.self, forKey: key))
        case .float:
            return .float(float: try container.decode(Float.self, forKey: key))
        case .date:
            return .date(date: try container.decode(Date.self, forKey: key))
        }
    }
    
    func encodeVariable<Key: CodingKey>(
        _ variable: Variable?,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        guard let variable else { return }
        try validate(variable)
        
        switch variable {
        case .string(let value):
            try container.encode(value, forKey: key)
        case .date(let date):
            try container.encode(date, forKey: key)
        case .int(let int):
            try container.encode(int, forKey: key)
        case .bool(let bool):
            try container.encode(bool, forKey: key)
        case .float(let float):
            try container.encode(float, forKey: key)
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

enum StepCodingMode {
    case program
    case execution
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

struct NumericExpression: Codable, ExpressibleByStringLiteral {
    var value: String
    
    init(_ value: String) {
        self.value = value
    }
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
    
    func variablesUsed() -> [String] {
        let expression = Expression(value)
        var seenVariables = Set<String>()
        
        return expression.symbols.compactMap { symbol -> String? in
            guard case .variable(let name) = symbol else { return nil }
            guard !seenVariables.contains(name) else { return nil }
            seenVariables.insert(name)
            return name
        }
    }
    
    func missingOrNonNumericVariables(in availableVariables: [String: Variable]) -> [String] {
        variablesUsed().filter { variableName in
            guard let variable = availableVariables[variableName] else { return true }
            return variable.numericValue == nil
        }
    }
    
    func canEvaluate(variables: [String: Variable]) -> Bool {
        missingOrNonNumericVariables(in: variables).isEmpty
    }
    
    func evaluate(variables: [String: Variable]) throws -> Float {
        guard canEvaluate(variables: variables) else {
            throw ComputeError.variableStorageMismatch
        }
        
        let constants = Dictionary(uniqueKeysWithValues: variablesUsed().map { variableName in
            (variableName, variables[variableName]!.numericValue!)
        })
        let expression = Expression(value, constants: constants)
        
        return Float(try expression.evaluate())
    }
}

struct TextStep: Step {
    var type = StepType.text
    var metadata: StepMetadata
    var message: String
    private var nextStepId: String?
    
    private enum CodingKeys: String, CodingKey {
        case metadata
        case message
        case next
    }
    
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = .text
        self.metadata = try container.decode(StepMetadata.self, forKey: .metadata)
        self.message = try container.decode(String.self, forKey: .message)
        self.nextStepId = try container.decodeIfPresent(String.self, forKey: .next)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(nextStepId, forKey: .next)
    }
}

struct InputStep: Step {
    var type = StepType.input
    var metadata: StepMetadata
    var inputKind: InputKind
    var label: String?
    var defaultValue: Variable?
    var value: Variable?
    var key: String
    private var nextStepId: String
    
    private enum CodingKeys: String, CodingKey {
        case metadata
        case input
        case label
        case defaultValue
        case value
        case key
        case next
    }
    
    func compute(variables: [String : Variable]) throws -> any Step {
        var copy = self
        copy.label = label != nil ? (try? Parser.interpolate(label!, variables: variables)) : nil
        if (variables.keys.contains(key)) {
            copy.value = variables[key]
        } else if copy.value == nil {
            copy.value = defaultValue
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
    
    init(from decoder: Decoder) throws {
        try self.init(from: decoder, mode: .program)
    }
    
    init(from decoder: Decoder, mode: StepCodingMode) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = .input
        self.metadata = try container.decode(StepMetadata.self, forKey: .metadata)
        self.inputKind = try container.decode(InputKind.self, forKey: .input)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        switch mode {
        case .program:
            self.defaultValue = try inputKind.decodeVariable(from: container, forKey: .defaultValue)
            self.value = nil
        case .execution:
            self.defaultValue = nil
            self.value = try inputKind.decodeVariable(from: container, forKey: .value)
        }
        self.key = try container.decode(String.self, forKey: .key)
        self.nextStepId = try container.decode(String.self, forKey: .next)
    }
    
    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, mode: .program)
    }
    
    func encode(to encoder: Encoder, mode: StepCodingMode) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(inputKind, forKey: .input)
        try container.encodeIfPresent(label, forKey: .label)
        switch mode {
        case .program:
            try inputKind.encodeVariable(defaultValue, to: &container, forKey: .defaultValue)
        case .execution:
            try inputKind.encodeVariable(value, to: &container, forKey: .value)
        }
        try container.encode(key, forKey: .key)
        try container.encode(nextStepId, forKey: .next)
    }
}

indirect enum ConditionalExpression: Codable {
    
    enum VariableOrKindEnum: Codable {
        case variable(name: String)
        case string(value: String)
        case date(value: Date)
        case numeric(value: Float)
        case numericExpression(value: NumericExpression)
        case boolean(value: Bool)
        
        private enum CodingKeys: String, CodingKey {
            case variable = "var"
            case expression
            case date
        }
        
        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer() {
                if let value = try? container.decode(Bool.self) {
                    self = .boolean(value: value)
                    return
                }
                if let value = try? container.decode(Float.self) {
                    self = .numeric(value: value)
                    return
                }
                if let value = try? container.decode(String.self) {
                    self = .string(value: value)
                    return
                }
            }
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let name = try container.decodeIfPresent(String.self, forKey: .variable) {
                self = .variable(name: name)
            } else if let expression = try container.decodeIfPresent(NumericExpression.self, forKey: .expression) {
                self = .numericExpression(value: expression)
            } else if let date = try container.decodeIfPresent(Date.self, forKey: .date) {
                self = .date(value: date)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .variable,
                    in: container,
                    debugDescription: "Expected a conditional operand."
                )
            }
        }
        
        func encode(to encoder: Encoder) throws {
            switch self {
            case .variable(let name):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .variable)
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .date(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(value, forKey: .date)
            case .numeric(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .numericExpression(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(value, forKey: .expression)
            case .boolean(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            }
        }
        
        func stringValue(variables: [String: Variable]) throws -> String {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .string else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "string", actual: value.storageMediumRepresentation().rawValue)
                }
                return value.interpolatedValue
            case .string(value: let value):
                return value
            case .boolean:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "boolean")
            case .date:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "date")
            case .numeric:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numeric")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")
            }
        }
        
        func dateValue(variables: [String: Variable]) throws -> Date {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .date else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "date", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let dateValue = value.dateValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "date")
                }
                return dateValue
            case .date(value: let value):
                return value
            case .boolean:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "boolean")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "string")
            case .numeric:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "numeric")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")
            }
        }
        
        func numericValue(variables: [String: Variable]) throws -> Float {
            switch self {
                case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .float || value.storageMediumRepresentation() == .int else {
                        throw ConditionalExpressionError.variableWrongType(name: name, expected: "numeric", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let numericValue = value.numericValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "numeric")
                }
                return Float(numericValue)
                case .numeric(value: let value):
                return value
            case .numericExpression(value: let value):
                return try value.evaluate(variables: variables)
            case .boolean:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "boolean")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "string")
            case .date:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "date")
                
            }
        }
        
        func booleanValue(variables: [String: Variable]) throws -> Bool {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .bool else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "boolean", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let booleanValue = value.booleanValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "boolean")
                }
                return booleanValue
            case .boolean(value: let value):
                return value
            case .date:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "date")
            case .numeric:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "numeric")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "string")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")

            }
        }
    }
    
    case greaterThan(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case lessThan(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case equal(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum)
    case valueIn(type: String, lhs: VariableOrKindEnum, rhs: [VariableOrKindEnum])
    case and(expressions: [ConditionalExpression])
    case or(expressions: [ConditionalExpression])
    case negate(expression: ConditionalExpression)
    case boolean(value: VariableOrKindEnum)
    case before(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case after(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case sameDay(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum)
    
    private enum CodingKeys: String, CodingKey {
        case op
        case type
        case lhs
        case rhs
        case orEqual
        case expressions
        case expression
        case value
    }
    
    private enum ConditionOperator: String, Codable {
        case greaterThan
        case lessThan
        case equal
        case valueIn = "in"
        case and
        case or
        case not
        case boolean
        case before
        case after
        case sameDay
    }
    
    enum ConditionalExpressionError: Error {
        case variableUnexpectedValue(expected: String)
        case wrongType(expected: String, actual: String)
        case variableNotFound(name: String)
        case variableWrongType(name: String, expected: String, actual: String)
        case unexpectedComparison(lhs: String, rhs: String)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(ConditionOperator.self, forKey: .op)
        
        switch op {
        case .greaterThan:
            self = .greaterThan(
                type: try container.decode(String.self, forKey: .type),
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs),
                orEqual: try container.decodeIfPresent(Bool.self, forKey: .orEqual) ?? false
            )
        case .lessThan:
            self = .lessThan(
                type: try container.decode(String.self, forKey: .type),
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs),
                orEqual: try container.decodeIfPresent(Bool.self, forKey: .orEqual) ?? false
            )
        case .equal:
            self = .equal(
                type: try container.decode(String.self, forKey: .type),
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs)
            )
        case .valueIn:
            self = .valueIn(
                type: try container.decode(String.self, forKey: .type),
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode([VariableOrKindEnum].self, forKey: .rhs)
            )
        case .and:
            self = .and(expressions: try container.decode([ConditionalExpression].self, forKey: .expressions))
        case .or:
            self = .or(expressions: try container.decode([ConditionalExpression].self, forKey: .expressions))
        case .not:
            self = .negate(expression: try container.decode(ConditionalExpression.self, forKey: .expression))
        case .boolean:
            self = .boolean(value: try container.decode(VariableOrKindEnum.self, forKey: .value))
        case .before:
            self = .before(
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs),
                orEqual: try container.decodeIfPresent(Bool.self, forKey: .orEqual) ?? false
            )
        case .after:
            self = .after(
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs),
                orEqual: try container.decodeIfPresent(Bool.self, forKey: .orEqual) ?? false
            )
        case .sameDay:
            self = .sameDay(
                lhs: try container.decode(VariableOrKindEnum.self, forKey: .lhs),
                rhs: try container.decode(VariableOrKindEnum.self, forKey: .rhs)
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .greaterThan(let type, let lhs, let rhs, let orEqual):
            try container.encode(ConditionOperator.greaterThan, forKey: .op)
            try container.encode(type, forKey: .type)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
            try container.encode(orEqual, forKey: .orEqual)
        case .lessThan(let type, let lhs, let rhs, let orEqual):
            try container.encode(ConditionOperator.lessThan, forKey: .op)
            try container.encode(type, forKey: .type)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
            try container.encode(orEqual, forKey: .orEqual)
        case .equal(let type, let lhs, let rhs):
            try container.encode(ConditionOperator.equal, forKey: .op)
            try container.encode(type, forKey: .type)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .valueIn(let type, let lhs, let rhs):
            try container.encode(ConditionOperator.valueIn, forKey: .op)
            try container.encode(type, forKey: .type)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .and(let expressions):
            try container.encode(ConditionOperator.and, forKey: .op)
            try container.encode(expressions, forKey: .expressions)
        case .or(let expressions):
            try container.encode(ConditionOperator.or, forKey: .op)
            try container.encode(expressions, forKey: .expressions)
        case .negate(let expression):
            try container.encode(ConditionOperator.not, forKey: .op)
            try container.encode(expression, forKey: .expression)
        case .boolean(let value):
            try container.encode(ConditionOperator.boolean, forKey: .op)
            try container.encode(value, forKey: .value)
        case .before(let lhs, let rhs, let orEqual):
            try container.encode(ConditionOperator.before, forKey: .op)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
            try container.encode(orEqual, forKey: .orEqual)
        case .after(let lhs, let rhs, let orEqual):
            try container.encode(ConditionOperator.after, forKey: .op)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
            try container.encode(orEqual, forKey: .orEqual)
        case .sameDay(let lhs, let rhs):
            try container.encode(ConditionOperator.sameDay, forKey: .op)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        }
    }
    
    func evaluate(variables: [String: Variable]) throws -> Bool {
        switch self {
        case .boolean(value: let val):
            return try val.booleanValue(variables: variables)
        case .negate(expression: let expression):
            return !(try expression.evaluate(variables: variables))
        case .and(expressions: let expressions):
            return try expressions.allSatisfy({try $0.evaluate(variables: variables)})
        case .or(expressions: let expressions):
            return try expressions.contains(where: { try $0.evaluate(variables: variables)})
        case .greaterThan(type: let type, lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a > b || (orEqual && a == b)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a > b || (orEqual && a == b)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return !a && b || (orEqual && a == b)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a > b || (orEqual && a == b)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .lessThan(type: let type, lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a < b || (orEqual && a == b)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a < b || (orEqual && a == b)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return !a && b || (orEqual && a == b)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a < b || (orEqual && a == b)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .equal(type: let type, lhs: let lhs, rhs: let rhs):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a == b
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a == b
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return a == b
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a == b
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .valueIn(type: let type, lhs: let lhs, rhs: let rhs):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.map({try $0.stringValue(variables: variables)})
                return b.contains(a)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.map({try $0.dateValue(variables: variables)})
                return b.contains(a)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.map({try $0.booleanValue(variables: variables)})
                return b.contains(a)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.map({try $0.numericValue(variables: variables)})
                return b.contains(a)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .before(lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            let lhsDate = try lhs.dateValue(variables: variables)
            let rhsDate = try rhs.dateValue(variables: variables)
            return lhsDate.timeIntervalSince(rhsDate) < 0 || (orEqual && lhsDate.timeIntervalSince(rhsDate) == 0)
        case .after(lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            let lhsDate = try lhs.dateValue(variables: variables)
            let rhsDate = try rhs.dateValue(variables: variables)
            return lhsDate.timeIntervalSince(rhsDate) > 0 || (orEqual && lhsDate.timeIntervalSince(rhsDate) == 0)
        case .sameDay(lhs: let lhs, rhs: let rhs):
            return Calendar.current.isDate(try lhs.dateValue(variables: variables), inSameDayAs: try rhs.dateValue(variables: variables))
        }
    }
}

struct ConditionalStep: Step {
    var type = StepType.conditional
    var metadata: StepMetadata
    var condition: ConditionalExpression
    var trueStepId: String
    var falseStepId: String
    var result: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case metadata
        case condition
        case trueStep = "true"
        case falseStep = "false"
        case result
    }
    
    func compute(variables: [String : Variable]) throws -> any Step {
        var copy = self
        copy.result = try condition.evaluate(variables: variables)
        return copy
    }
    
    func getNextStep() -> String? {
        guard let result = result else {
            return nil
        }
        return result ? trueStepId : falseStepId
    }
    
    init(from decoder: Decoder) throws {
        try self.init(from: decoder, mode: .program)
    }
    
    init(from decoder: Decoder, mode: StepCodingMode) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = .conditional
        self.metadata = try container.decode(StepMetadata.self, forKey: .metadata)
        self.condition = try container.decode(ConditionalExpression.self, forKey: .condition)
        self.trueStepId = try container.decode(String.self, forKey: .trueStep)
        self.falseStepId = try container.decode(String.self, forKey: .falseStep)
        switch mode {
        case .program:
            self.result = nil
        case .execution:
            self.result = try container.decodeIfPresent(Bool.self, forKey: .result)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, mode: .program)
    }
    
    func encode(to encoder: Encoder, mode: StepCodingMode) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(condition, forKey: .condition)
        try container.encode(trueStepId, forKey: .trueStep)
        try container.encode(falseStepId, forKey: .falseStep)
        if mode == .execution {
            try container.encodeIfPresent(result, forKey: .result)
        }
    }
}

struct ComputeStep: Step {
    var type = StepType.compute
    var metadata: StepMetadata
    var key: String
    var expression: NumericExpression
    var computedValue: Float?
    var nextStepId: String
    
    private enum CodingKeys: String, CodingKey {
        case metadata
        case key
        case expression
        case computedValue
        case next
    }
    
    func expressionVariables() -> [String] {
        expression.variablesUsed()
    }
    
    func missingOrNonNumericVariables(in availableVariables: [String: Variable]) -> [String] {
        expression.missingOrNonNumericVariables(in: availableVariables)
    }
    
    func canEvaluate(variables: [String: Variable]) -> Bool {
        expression.canEvaluate(variables: variables)
    }
    
    func compute(variables: [String: Variable]) throws -> any Step {
        var copy = self
        copy.computedValue = try expression.evaluate(variables: variables)
        return copy
    }
    
    func canComplete(with variables: [String : Variable]) throws -> Bool {
        canEvaluate(variables: variables)
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
    
    init(from decoder: Decoder) throws {
        try self.init(from: decoder, mode: .program)
    }
    
    init(from decoder: Decoder, mode: StepCodingMode) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = .compute
        self.metadata = try container.decode(StepMetadata.self, forKey: .metadata)
        self.key = try container.decode(String.self, forKey: .key)
        self.expression = try container.decode(NumericExpression.self, forKey: .expression)
        switch mode {
        case .program:
            self.computedValue = nil
        case .execution:
            self.computedValue = try container.decodeIfPresent(Float.self, forKey: .computedValue)
        }
        self.nextStepId = try container.decode(String.self, forKey: .next)
    }
    
    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, mode: .program)
    }
    
    func encode(to encoder: Encoder, mode: StepCodingMode) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(key, forKey: .key)
        try container.encode(expression, forKey: .expression)
        if mode == .execution {
            try container.encodeIfPresent(computedValue, forKey: .computedValue)
        }
        try container.encode(nextStepId, forKey: .next)
    }
}


struct StepEnvelope {
    let step: Step
}

extension StepEnvelope: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: any Decoder) throws {
        try self.init(from: decoder, mode: .program)
    }
    
    init(from decoder: any Decoder, mode: StepCodingMode) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        
        switch type {
        case .text:
            self.step = try TextStep(from: decoder)
        case .input:
            self.step = try InputStep(from: decoder, mode: mode)
        case .compute:
            self.step = try ComputeStep(from: decoder, mode: mode)
        case .conditional:
            self.step = try ConditionalStep(from: decoder, mode: mode)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, mode: .program)
    }
    
    func encode(to encoder: Encoder, mode: StepCodingMode) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step.type, forKey: .type)
        
        switch step {
        case let textStep as TextStep:
            try textStep.encode(to: encoder)
        case let inputStep as InputStep:
            try inputStep.encode(to: encoder, mode: mode)
        case let computeStep as ComputeStep:
            try computeStep.encode(to: encoder, mode: mode)
        case let conditionalStep as ConditionalStep:
            try conditionalStep.encode(to: encoder, mode: mode)
        default:
            try step.encode(to: encoder)
        }
    }
}
