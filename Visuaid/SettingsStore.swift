//
//  SettingsStore.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//

import SwiftUI
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var ttsEnabled: Bool = true
    @Published var defaultColorBlindness: ColorBlindnessMode = .none

    // Placeholders para futuras mejoras
    @Published var brightness: Double = 0.0
    @Published var contrast: Double = 1.0
    @Published var sensitivity: Double = 0.5
}

