//
//  MascotLog.swift
//  MascotKit
//

import os

enum MascotLog {
    static let content = Logger(subsystem: "MascotKit", category: "content")
    static let validation = Logger(subsystem: "MascotKit", category: "validation")
}
