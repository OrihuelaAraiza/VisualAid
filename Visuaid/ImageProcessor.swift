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

    // Suavizado temporal del color dominante (EMA HSV legacy - mantenido para compatibilidad)
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

        // Aplica solo el filtro de daltonismo (si corresponde) para la salida visual
        if colorBlindness != .none {
            ciImage = applyColorBlindnessFilter(ciImage, mode: colorBlindness)
        }

        // Render a CGImage para mostrar
        if let cg = renderCGImage(from: ciImage) {
            self.outputCGImage = cg
        }

        // NOTA: El pipeline robusto de color dominante se ejecuta desde el ViewModel llamando a:
        // computeDominantRGB(from:) sobre un ROI con Gray-World + k-means.
        // Aquí no actualizamos lastDominantName directamente para evitar parpadeos.
    }

    // Permite actualizar el nombre dominante desde el pipeline robusto externo (ViewModel)
    func setDominantName(_ name: String) {
        self.lastDominantName = name
    }

    // MARK: - API pública para pipeline robusto (invocada por el ViewModel)

    // Calcula el color dominante (sRGB 0..1) usando:
    // ROI central → Gray-World (ganancia estimada en downscale) → k-means (k=3)
    func computeDominantRGB(from sourceCI: CIImage, roiSize: CGFloat = 120) -> (CGFloat, CGFloat, CGFloat)? {
        // 1) ROI central
        let roiRect = centerROI(for: sourceCI, size: roiSize)
        let roiCI = crop(sourceCI, to: roiRect)

        // 2) Downscale a 64px para estimar Gray-World
        guard let smallCG = downscale(roiCI, to: 64) else { return nil }
        let gain = grayWorldGain(for: smallCG)

        // 3) Aplica ganancia al ROI original (corrección de iluminación)
        let correctedCI = applyGain(roiCI, gain: gain)

        // 4) Downscale del ROI corregido para extraer píxeles y aplicar k-means
        guard let correctedSmallCG = downscale(correctedCI, to: 64) else { return nil }
        let rgb = pixels(from: correctedSmallCG)
        guard !rgb.isEmpty else { return nil }

        // 5) k-means para color dominante
        return kMeansDominant(rgb, k: 3, iters: 8)
    }

    // MARK: - ROI

    // ROI cuadrado centrado en la imagen (en coordenadas CIImage)
    func centerROI(for image: CIImage, size: CGFloat = 120) -> CGRect {
        let extent = image.extent.integral
        let w = extent.width
        let h = extent.height
        let roiSize = min(size, min(w, h))
        let x = extent.midX - roiSize / 2.0
        let y = extent.midY - roiSize / 2.0
        return CGRect(x: x, y: y, width: roiSize, height: roiSize)
    }

    // Recorta la imagen a un rectángulo
    func crop(_ image: CIImage, to rect: CGRect) -> CIImage {
        return image.cropped(to: rect)
    }

    // MARK: - Gray-World

    // Estima ganancias por canal para llevar R,G,B a un gris promedio (Gray-World)
    func grayWorldGain(for cg: CGImage) -> (CGFloat, CGFloat, CGFloat) {
        let width = cg.width
        let height = cg.height
        guard let data = cg.dataProvider?.data as Data? else {
            return (1, 1, 1)
        }
        // Nota: el orden de bytes del video es BGRA en muchos casos, pero CGImage que generamos con CIContext
        // al usar colorSpace sRGB y RGBA8 suele venir como RGBA (byteOrder32Big premultipliedLast).
        // Para robustez, usamos CGImage API de lectura directa:
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return (1, 1, 1) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let outData = ctx.data else { return (1, 1, 1) }

        let ptr = outData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var sumR: CGFloat = 0, sumG: CGFloat = 0, sumB: CGFloat = 0
        var count: CGFloat = 0

        let bytesPerRow = ctx.bytesPerRow
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let o = row + x * 4
                let r = CGFloat(ptr[o + 0]) / 255.0
                let g = CGFloat(ptr[o + 1]) / 255.0
                let b = CGFloat(ptr[o + 2]) / 255.0
                sumR += r; sumG += g; sumB += b
                count += 1
            }
        }
        guard count > 0 else { return (1, 1, 1) }
        let meanR = sumR / count
        let meanG = sumG / count
        let meanB = sumB / count
        let meanGray = (meanR + meanG + meanB) / 3.0
        func safeGain(_ m: CGFloat) -> CGFloat {
            let eps: CGFloat = 1e-4
            return (m > eps) ? (meanGray / m) : 1.0
        }
        return (safeGain(meanR), safeGain(meanG), safeGain(meanB))
    }

    // Aplica ganancias por canal con CIColorMatrix (multiplica R,G,B por sus factores)
    func applyGain(_ ci: CIImage, gain: (CGFloat, CGFloat, CGFloat)) -> CIImage {
        let (gr, gg, gb) = gain
        return ci.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gr, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gg, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gb, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    // MARK: - Downscale y lectura de píxeles

    // Reduce manteniendo aspecto para que el lado mayor sea maxSide (salida CGImage RGBA8 sRGB)
    func downscale(_ image: CIImage, to maxSide: CGFloat) -> CGImage? {
        let extent = image.extent.integral
        let w = extent.width, h = extent.height
        guard w > 1, h > 1 else { return nil }
        let scale = maxSide / max(w, h)
        let targetW = max(1, Int(w * scale))
        let targetH = max(1, Int(h * scale))

        // CILanczosScaleTransform para calidad
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = image
        scaleFilter.scale = Float(scale)
        scaleFilter.aspectRatio = 1.0
        let scaled = scaleFilter.outputImage ?? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        return ciContext.createCGImage(scaled, from: scaled.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    // Extrae píxeles como sRGB 0..1 (suponiendo CGImage RGBA8 sRGB)
    func pixels(from cg: CGImage) -> [(CGFloat, CGFloat, CGFloat)] {
        let width = cg.width
        let height = cg.height

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let outData = ctx.data else { return [] }

        let bytesPerRow = ctx.bytesPerRow
        let ptr = outData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var result: [(CGFloat, CGFloat, CGFloat)] = []
        result.reserveCapacity(width * height)

        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let o = row + x * 4
                let r = CGFloat(ptr[o + 0]) / 255.0
                let g = CGFloat(ptr[o + 1]) / 255.0
                let b = CGFloat(ptr[o + 2]) / 255.0
                result.append((r, g, b))
            }
        }
        return result
    }

    // MARK: - k-means simple en sRGB

    // Devuelve el centro del clúster más numeroso
    func kMeansDominant(_ rgb: [(CGFloat, CGFloat, CGFloat)], k: Int = 3, iters: Int = 8) -> (CGFloat, CGFloat, CGFloat)? {
        guard !rgb.isEmpty, k > 0 else { return nil }
        let n = rgb.count
        let kClamped = min(k, max(1, min(6, n)))

        // Inicialización: muestras espaciadas
        var centers: [(CGFloat, CGFloat, CGFloat)] = []
        let step = max(1, n / kClamped)
        for i in 0..<kClamped {
            centers.append(rgb[min(i * step, n - 1)])
        }

        var assignments = [Int](repeating: 0, count: n)

        func dist2(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
            let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
            return dr*dr + dg*dg + db*db
        }

        for _ in 0..<iters {
            // Asignación
            for i in 0..<n {
                var bestK = 0
                var bestD = CGFloat.greatestFiniteMagnitude
                let p = rgb[i]
                for c in 0..<centers.count {
                    let d = dist2(p, centers[c])
                    if d < bestD {
                        bestD = d
                        bestK = c
                    }
                }
                assignments[i] = bestK
            }
            // Recalcular centros
            var sumR = [CGFloat](repeating: 0, count: centers.count)
            var sumG = [CGFloat](repeating: 0, count: centers.count)
            var sumB = [CGFloat](repeating: 0, count: centers.count)
            var count = [Int](repeating: 0, count: centers.count)

            for i in 0..<n {
                let k = assignments[i]
                let p = rgb[i]
                sumR[k] += p.0
                sumG[k] += p.1
                sumB[k] += p.2
                count[k] += 1
            }
            for c in 0..<centers.count {
                if count[c] > 0 {
                    centers[c] = (sumR[c] / CGFloat(count[c]),
                                  sumG[c] / CGFloat(count[c]),
                                  sumB[c] / CGFloat(count[c]))
                }
            }
        }

        // Selecciona el clúster más grande
        var counts = [Int](repeating: 0, count: centers.count)
        for k in assignments { counts[k] += 1 }
        guard let maxIndex = counts.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return centers.first
        }
        return centers[maxIndex]
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

    // MARK: - Suavizado HSV legacy (no usado en el nuevo pipeline, mantenido por compatibilidad)

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
