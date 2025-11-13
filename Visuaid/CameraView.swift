//
//  CameraView.swift
//  Visuaid
//
//  Created by JP on 11/11/25.
//

import SwiftUI
import AVFoundation
import Vision

struct CameraView: View {
    @StateObject private var camera = CameraService()

    // Ahora son inyectados desde fuera para evitar duplicados y permitir el pipeline en el VM
    @ObservedObject var processor: ImageProcessor
    @ObservedObject var speaker: ColorSpeaker

    // UI mínima
    @State private var selectedDaltonism: ColorBlindnessMode = .none

    // Control de actividad/visibilidad
    @State private var isActive: Bool = true

    var body: some View {
        ZStack {
            CameraFeedView(
                outputCGImage: processor.outputCGImage
            )
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()
        }
        .task {
            do {
                try await camera.configure()
                camera.onSampleBuffer = { [weak processor] buffer in
                    Task { @MainActor in
                        if isActive {
                            processor?.process(sampleBuffer: buffer)
                        }
                    }
                }
                camera.start()
            } catch {
                // Puedes mostrar una alerta si lo deseas
            }
        }
        .onAppear {
            isActive = true
            processor.colorBlindness = selectedDaltonism
            // El speaker.isEnabled ya se sincroniza desde Settings en el ViewModel
        }
        .onDisappear {
            isActive = false
        }
        .onChange(of: selectedDaltonism) { _, v in processor.colorBlindness = v }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visuaid")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                if !processor.lastDominantName.isEmpty {
                    Text(processor.lastDominantName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { speaker.isEnabled },
                set: { speaker.isEnabled = $0 }
            )) {
                Image(systemName: speaker.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.white)
            Picker("Daltonismo", selection: $selectedDaltonism) {
                ForEach(ColorBlindnessMode.allCases) { m in
                    Text(m.rawValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .tag(m)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }
}

private struct CameraFeedView: View {
    let outputCGImage: CGImage?

    var body: some View {
        Group {
            if let cg = outputCGImage {
                GeometryReader { geo in
                    let size: CGSize = geo.size
                    let img = Image(decorative: cg, scale: 1, orientation: .up)

                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
            } else {
                ZStack {
                    Rectangle().fill(.black.opacity(0.95))
                    ProgressView("Iniciando cámara…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

