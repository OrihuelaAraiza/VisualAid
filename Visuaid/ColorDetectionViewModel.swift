//
//  ColorDetectionViewModel.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//

import Foundation
import Combine

@MainActor
final class ColorDetectionViewModel: ObservableObject {
    @Published private(set) var settings: SettingsStore

    // Dependencias de flujo de color y voz
    @Published private(set) var processor: ImageProcessor
    @Published private(set) var speaker: ColorSpeaker

    // Control
    private var cancellables = Set<AnyCancellable>()

    // Ajuste de estabilidad (ms)
    var debounceMilliseconds: Int = 500

    // Init designado: recibe dependencias ya creadas
    init(settings: SettingsStore, processor: ImageProcessor, speaker: ColorSpeaker) {
        self.settings = settings
        self.processor = processor
        self.speaker = speaker
        bindColorToSpeech()
    }

    // Init de conveniencia para crear dependencias en MainActor de forma segura
    convenience init(settings: SettingsStore) {
        self.init(settings: settings, processor: ImageProcessor(), speaker: ColorSpeaker())
    }

    private func bindColorToSpeech() {
        // Sincroniza flag de voz desde settings
        settings.$ttsEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.speaker.isEnabled = enabled
            }
            .store(in: &cancellables)

        // Pipeline: nombre dominante → debounce → no repetir → hablar
        processor.$lastDominantName
            .removeDuplicates() // 3) No repetir si no cambió
            .debounce(for: .milliseconds(debounceMilliseconds), scheduler: RunLoop.main) // 2) Debounce
            .sink { [weak self] name in
                guard let self else { return }
                guard !name.isEmpty else { return }
                guard self.settings.ttsEnabled else { return }

                // 1) Vaciar la cola antes de hablar
                self.speaker.stopSpeaking()
                self.speaker.speak(name)
            }
            .store(in: &cancellables)
    }
}

