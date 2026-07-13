//
//  Program.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import VersionedCodable

struct Program {
    let title: String
    let authorName: String
    let description: String
    let steps: [StepEnvelope]
    
    enum ValidationError: Error {
        case repeatedIds
    }
    
    func validate() throws -> Void {
        if (Set(steps.map({$0.step.id})).count != steps.count) {
            throw ValidationError.repeatedIds
        }
    }
}

extension Program: VersionedCodable {
    static let version: Int? = 1
    typealias PreviousVersion = NothingEarlier
}
