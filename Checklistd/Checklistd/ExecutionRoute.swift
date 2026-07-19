//
//  ExecutionRoute.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//

import Foundation

enum ExecutionRoute: Hashable {
    case repository(String)
    case file(URL)
    case creating(String)
}
