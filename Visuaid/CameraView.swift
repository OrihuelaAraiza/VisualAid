//
//  CameraView.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Vista principal: integra captura de cámara + procesamiento + overlay de contornos + controles UI.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var camera = CameraService()
    @StateObject private var processor = ImageProcessor()
    @StateObject private var speaker = ColorSpeaker()

    // Controles UI
    @State private var selectedProcessing: ProcessingMode = .original
    @State private var selectedThreshold: ThresholdMode = .global
    @State private var selectedEdges: EdgeMode = .none
    @State private var selectedDaltonism: ColorBlindnessMode = .none
    @State private var globalT: Double = 0.5
    @State private var adaptiveC: Double = 0.05
    @State private var showContours = false
    @State private var speakColor = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let cg = processor.outputCGImage {
                    GeometryReader { geo in
                        let size = geo.size
                        let image = Image(decorative: cg, scale: 1, orientation: .up, label: Text("Camera"))
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .overlay(
                                ContourOverlay(contours: processor.contours,
                                               imageSize: CGSize(width: cg.width, height: cg.height),
                                               strokeColor: .yellow)
                                    .opacity(showContours ? 1 : 0)
                            )
                    }
                } else {
                    Rectangle().fill(.black.opacity(0.95))
                    ProgressView("Iniciando cámara…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
                .padding()
            }
        }
        .onChange(of: processor.lastDominantName) { _, new in
            if speakColor {
                speaker.speak(new)
            }
        }
        .task {
            do {
                try await camera.configure()
                camera.onSampleBuffer = { [weak processor] buffer in
                    Task { @MainActor in processor?.process(sampleBuffer: buffer) }
                }
                camera.start()
            } catch {
                // Manejo simple de error de permisos/configuración
            }
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: selectedProcessing) { _, v in processor.processingMode = v }
        .onChange(of: selectedThreshold) { _, v in processor.thresholdMode = v }
        .onChange(of: selectedEdges) { _, v in processor.edgeMode = v }
        .onChange(of: selectedDaltonism) { _, v in processor.colorBlindness = v }
        .onChange(of: globalT) { _, v in processor.globalThreshold = Float(v) }
        .onChange(of: adaptiveC) { _, v in processor.adaptiveC = Float(v) }
        .onChange(of: showContours) { _, v in processor.showContours = v }
        .onChange(of: speakColor) { _, v in speaker.isEnabled = v }
        .onAppear {
            // Inicializar estados en el procesador/speaker
            processor.processingMode = selectedProcessing
            processor.thresholdMode = selectedThreshold
            processor.edgeMode = selectedEdges
            processor.colorBlindness = selectedDaltonism
            processor.globalThreshold = Float(globalT)
            processor.adaptiveC = Float(adaptiveC)
            processor.showContours = showContours
            speaker.isEnabled = speakColor
        }
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
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
            Toggle(isOn: $speakColor) {
                Image(systemName: speakColor ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Modo de procesamiento
            Picker("Modo", selection: $selectedProcessing) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                // Umbral
                VStack(alignment: .leading) {
                    Picker("Threshold", selection: $selectedThreshold) {
                        ForEach(ThresholdMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedThreshold == .global {
                        HStack {
                            Text("T")
                            Slider(value: $globalT, in: 0...1)
                            Text(String(format: "%.2f", globalT))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    } else {
                        HStack {
                            Text("C")
                            Slider(value: $adaptiveC, in: 0...0.3)
                            Text(String(format: "%.2f", adaptiveC))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                // Bordes
                VStack(alignment: .leading) {
                    Picker("Bordes", selection: $selectedEdges) {
                        ForEach(EdgeMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Contornos", isOn: $showContours)
                        .toggleStyle(.switch)
                }
            }

            // Daltonismo
            HStack {
                Image(systemName: "eye.fill")
                Picker("Daltonismo", selection: $selectedDaltonism) {
                    ForEach(ColorBlindnessMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }
}
