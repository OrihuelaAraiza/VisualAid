//
//  ColorDetectionViewModel.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//

import Foundation
import Combine
import CoreImage
import AVFoundation
import CoreGraphics
import SwiftUI

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

    // Pipeline de estabilidad del color
    private var emaRGB: (r: CGFloat, g: CGFloat, b: CGFloat)?
    private let alphaEMA: CGFloat = 0.35

    // Histeresis
    private var lastHSV: HSV?
    private let minHueChange: CGFloat = 10.0
    private let minSChange: CGFloat = 0.08
    private let minVChange: CGFloat = 0.08

    // Init designado: recibe dependencias ya creadas
    init(settings: SettingsStore, processor: ImageProcessor, speaker: ColorSpeaker) {
        self.settings = settings
        self.processor = processor
        self.speaker = speaker
        bindColorToSpeech()
        bindCameraFrames()
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
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceMilliseconds), scheduler: RunLoop.main)
            .sink { [weak self] name in
                guard let self else { return }
                guard !name.isEmpty else { return }
                guard self.settings.ttsEnabled else { return }
                // Vaciar cola antes de hablar
                self.speaker.stopSpeaking()
                self.speaker.speak(name)
            }
            .store(in: &cancellables)
    }

    // Suscríbete al CGImage de salida para ejecutar el pipeline robusto sobre el frame actual
    private func bindCameraFrames() {
        processor.$outputCGImage
            .compactMap { $0 } // solo frames válidos
            .receive(on: RunLoop.main)
            .sink { [weak self] cg in
                guard let self else { return }
                self.processDominantColor(fromRendered: cg)
            }
            .store(in: &cancellables)
    }

    // Ejecuta: ROI → Gray-World → k-means → EMA → Histeresis → Naming CIEDE2000
    private func processDominantColor(fromRendered cgImage: CGImage) {
        // Usamos el mismo frame renderizado para mantener consistencia con filtros de daltonismo ya aplicados en pantalla.
        let ci = CIImage(cgImage: cgImage).oriented(.up)

        // 1-3) Pipeline robusto en el ImageProcessor
        guard let rgb = processor.computeDominantRGB(from: ci, roiSize: 120) else { return }

        // 4) EMA para evitar parpadeo
        let smoothed = smoothEMA(rgb: rgb)

        // 5) Histeresis en HSV
        let hsv = ColorUtilities.rgbToHSV(r: smoothed.r, g: smoothed.g, b: smoothed.b)
        if isSignificantChange(new: hsv, prev: lastHSV) {
            lastHSV = hsv
            // 6) Naming ΔE2000
            let name = ColorUtilities.nearestNameByDE2000(r: smoothed.r, g: smoothed.g, b: smoothed.b)
            processor.setDominantName(name)
        }
    }

    // EMA exponencial: nuevo = alpha*actual + (1-alpha)*previo
    private func smoothEMA(rgb: (CGFloat, CGFloat, CGFloat)) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        if let prev = emaRGB {
            let r = alphaEMA * rgb.0 + (1 - alphaEMA) * prev.r
            let g = alphaEMA * rgb.1 + (1 - alphaEMA) * prev.g
            let b = alphaEMA * rgb.2 + (1 - alphaEMA) * prev.b
            let smoothed = (r: r, g: g, b: b)
            emaRGB = smoothed
            return smoothed
        } else {
            let initVal = (r: rgb.0, g: rgb.1, b: rgb.2)
            emaRGB = initVal
            return initVal
        }
    }

    private func isSignificantChange(new: HSV, prev: HSV?) -> Bool {
        guard let prev = prev else { return true }
        // Hue circular
        var dh = abs(new.h - prev.h)
        if dh > 180 { dh = 360 - dh }
        let ds = abs(new.s - prev.s)
        let dv = abs(new.v - prev.v)
        return dh >= minHueChange || ds >= minSChange || dv >= minVChange
    }
}
