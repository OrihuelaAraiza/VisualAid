//
//  ColorSpeaker.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Lectura por voz del color dominante con AVSpeechSynthesizer.
//

import AVFoundation
import Combine

@MainActor
final class ColorSpeaker: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isEnabled: Bool = false
    private var lastSpoken: String = ""
    private var lastSpeakTime: Date = .distantPast
    private let debounce: TimeInterval = 1.2
    private var didSpeakOnce: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Categoría de reproducción, mezcla con otros sonidos si es necesario
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            print("[Speaker] AudioSession configurada")
        } catch {
            print("[Speaker] Error configurando AudioSession: \(error)")
        }
    }

    func speak(_ text: String, locale: String = "es-MX") {
        guard isEnabled else {
            print("[Speaker] Ignorado (isEnabled=false)")
            return
        }
        guard !text.isEmpty else {
            print("[Speaker] Ignorado (texto vacío)")
            return
        }

        let now = Date()
        if didSpeakOnce {
            // Evita repetir demasiado frecuentemente el mismo texto
            if text == lastSpoken && now.timeIntervalSince(lastSpeakTime) <= debounce {
                print("[Speaker] Debounce activo (mismo texto, muy pronto)")
                return
            }
        }

        lastSpoken = text
        lastSpeakTime = now
        didSpeakOnce = true

        let utterance = AVSpeechUtterance(string: text)
        // Fallback de voz en español
        if let voice = AVSpeechSynthesisVoice(language: locale) ??
                       AVSpeechSynthesisVoice(language: "es-ES") ??
                       AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("es") }) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

        print("[Speaker] speak: \"\(text)\" voice=\(utterance.voice?.language ?? "nil") rate=\(utterance.rate)")
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        print("[Speaker] stopSpeaking()")
        synthesizer.stopSpeaking(at: .immediate)
    }

    func reset() {
        print("[Speaker] reset()")
        lastSpoken = ""
        didSpeakOnce = false
        lastSpeakTime = .distantPast
    }
}

extension ColorSpeaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("[Speaker] didStart utterance: \(utterance.speechString)")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[Speaker] didFinish utterance")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("[Speaker] didCancel utterance")
    }
}

