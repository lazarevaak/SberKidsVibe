//
//  MascotLog.swift
//  MascotKit
//
//  Системный журнал пакета. Видно в консоли Xcode и в приложении «Консоль» на Mac
//  (в том числе с подключённого телефона): фильтр по подсистеме «MascotKit».
//

import os

enum MascotLog {
    /// Загрузка контента: конфиг, персонаж, картинки, звуки.
    static let content = Logger(subsystem: "MascotKit", category: "content")
    /// Проверка конфига и персонажа — подсказки контент-менеджеру.
    static let validation = Logger(subsystem: "MascotKit", category: "validation")
}
