//
//  ImageProcessor.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Procesamiento centrado en simulación/corrección de daltonismo y color dominante.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import simd
import Combine
import UIKit

@MainActor
final class ImageProcessor: ObservableObject {
    // Única configuración relevante: daltonismo
    @Published var colorBlindness: ColorBlindnessMode = .none

    // Resultados
    @Published private(set) var outputCGImage: CGImage?
    @Published private(set) var lastDominantName: String = ""

    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Suavizado temporal del color dominante (EMA)
    private var emaHSV: HSV?
    private let alphaEMA: CGFloat = 0.25 // 0..1 (más alto = reacciona más rápido)

    init() {
        // CIContext con GPU
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    // Entrada: CVPixelBuffer desde la cámara
    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Mantén orientación .up si la conexión está en .portrait
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.up)

        // Aplica solo el filtro de daltonismo (si corresponde)
        if colorBlindness != .none {
            ciImage = applyColorBlindnessFilter(ciImage, mode: colorBlindness)
        }

        // Render a CGImage
        if let cg = renderCGImage(from: ciImage) {
            self.outputCGImage = cg

            // Color dominante (muestreo robusto + EMA)
            let hsvInstant = ColorUtilities.dominantHSV(from: cg)
            let hsvSmoothed = smoothHSV(hsvInstant)
            let name = ColorUtilities.descriptiveName(for: hsvSmoothed)
            self.lastDominantName = name
        }
    }

    // MARK: - Daltonismo (matrices 3x3)

    private func applyColorBlindnessFilter(_ image: CIImage, mode: ColorBlindnessMode) -> CIImage {
        switch mode {
        case .none:
            return image
        case .pseudo:
            // Pseudocolor simple: permutar canales
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .protanopia:
            return apply3x3Matrix(image, matrix: ColorUtilities.protanopiaMatrix)
        case .deuteranopia:
            return apply3x3Matrix(image, matrix: ColorUtilities.deuteranopiaMatrix)
        }
    }

    private func apply3x3Matrix(_ image: CIImage, matrix: simd_float3x3) -> CIImage {
        let r = matrix.columns.0
        let g = matrix.columns.1
        let b = matrix.columns.2
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(r.x), y: CGFloat(r.y), z: CGFloat(r.z), w: 0),
            "inputGVector": CIVector(x: CGFloat(g.x), y: CGFloat(g.y), z: CGFloat(g.z), w: 0),
            "inputBVector": CIVector(x: CGFloat(b.x), y: CGFloat(b.y), z: CGFloat(b.z), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    // MARK: - Dominante EMA

    private func smoothHSV(_ hsv: HSV) -> HSV {
        if let prev = emaHSV {
            let h = wrapHueEMA(prev: prev.h, new: hsv.h, alpha: alphaEMA)
            let s = prev.s * (1 - alphaEMA) + hsv.s * alphaEMA
            let v = prev.v * (1 - alphaEMA) + hsv.v * alphaEMA
            let smoothed = HSV(h: h, s: s, v: v)
            emaHSV = smoothed
            return smoothed
        } else {
            emaHSV = hsv
            return hsv
        }
    }

    private func wrapHueEMA(prev: CGFloat, new: CGFloat, alpha: CGFloat) -> CGFloat {
        var delta = new - prev
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        var result = prev + alpha * delta
        if result < 0 { result += 360 }
        if result >= 360 { result -= 360 }
        return result
    }

    // MARK: - Render

    private func renderCGImage(from image: CIImage) -> CGImage? {
        let rect = image.extent.integral
        return ciContext.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace)
    }
}

