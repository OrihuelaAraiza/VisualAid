//
//  ColorDetectionViewModel.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//

import Foundation

@MainActor
final class ColorDetectionViewModel: ObservableObject {
    @Published private(set) var settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }
}
