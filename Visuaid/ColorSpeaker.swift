//
//  ColorSpeaker.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Lectura por voz del color dominante con AVSpeechSynthesizer.
//

import AVFoundation

@MainActor
final class ColorSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isEnabled: Bool = false
    private var lastSpoken: String = ""
    private var lastSpeakTime: Date = .distantPast
    private let debounce: TimeInterval = 1.2

    func speak(_ text: String, locale: String = "es-MX") {
        guard isEnabled else { return }
        let now = Date()
        guard text != lastSpoken || now.timeIntervalSince(lastSpeakTime) > debounce else { return }
        lastSpoken = text
        lastSpeakTime = now

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
