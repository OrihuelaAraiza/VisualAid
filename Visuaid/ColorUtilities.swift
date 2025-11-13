//
//  ColorUtilities.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Conversiones RGB↔HSV↔Lab y naming de color dominante.
//  Mejora: cálculo robusto de color dominante, CIELab + ΔE2000 y paleta de nombres.
//

import CoreGraphics
import CoreImage
import SwiftUI
import simd

struct HSV {
    var h: CGFloat // 0...360
    var s: CGFloat // 0...1
    var v: CGFloat // 0...1
}

struct Lab {
    var L: CGFloat
    var a: CGFloat
    var b: CGFloat
}

enum ColorBlindnessMode: String, CaseIterable, Identifiable {
    case none = "Normal"
    case protanopia = "Protanopía"
    case deuteranopia = "Deuteranopía"
    case pseudo = "Pseudocolor"

    var id: String { rawValue }
}

enum ThresholdMode: String, CaseIterable, Identifiable {
    case global = "Global"
    case adaptive = "Adaptativo"

    var id: String { rawValue }
}

enum EdgeMode: String, CaseIterable, Identifiable {
    case none = "Ninguno"
    case sobel = "Sobel"
    case canny = "Canny"

    var id: String { rawValue }
}

enum ProcessingMode: String, CaseIterable, Identifiable {
    case original = "Original"
    case grayscale = "Grises"
    case threshold = "Threshold"
    case edges = "Bordes"
    case colorSegmentation = "Segmentación Color"

    var id: String { rawValue }
}

struct NamedRGB {
    let name: String
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

struct ColorUtilities {

    // MARK: - RGB ↔ HSV

    // RGB (0...1) → HSV
    static func rgbToHSV(r: CGFloat, g: CGFloat, b: CGFloat) -> HSV {
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        var h: CGFloat = 0
        let s: CGFloat = maxVal == 0 ? 0 : delta / maxVal
        let v: CGFloat = maxVal

        if delta != 0 {
            if maxVal == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxVal == g {
                h = 60 * (((b - r) / delta) + 2)
            } else {
                h = 60 * (((r - g) / delta) + 4)
            }
        }
        if h < 0 { h += 360 }

        return HSV(h: h, s: s, v: v)
    }

    // MARK: - sRGB (D65) → XYZ → Lab

    static func rgbToXYZ(r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        func pivotRGB(_ c: CGFloat) -> CGFloat {
            return (c <= 0.04045) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        let R = pivotRGB(r)
        let G = pivotRGB(g)
        let B = pivotRGB(b)

        // Matriz sRGB->XYZ (D65)
        let X = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B)
        let Y = (0.2126729 * R + 0.7151522 * G + 0.0721750 * B)
        let Z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B)
        return (X, Y, Z)
    }

    static func xyzToLab(X: CGFloat, Y: CGFloat, Z: CGFloat) -> Lab {
        // Blanco de referencia D65
        let Xn: CGFloat = 0.95047
        let Yn: CGFloat = 1.00000
        let Zn: CGFloat = 1.08883

        func f(_ t: CGFloat) -> CGFloat {
            let delta: CGFloat = 6.0 / 29.0
            let delta3 = delta * delta * delta
            return (t > delta3) ? pow(t, 1.0/3.0) : (t / (3 * delta * delta) + 4.0/29.0)
        }

        let fx = f(X / Xn)
        let fy = f(Y / Yn)
        let fz = f(Z / Zn)

        let L = (116 * fy) - 16
        let a = 500 * (fx - fy)
        let b = 200 * (fy - fz)
        return Lab(L: L, a: a, b: b)
    }

    static func rgbToLab(r: CGFloat, g: CGFloat, b: CGFloat) -> Lab {
        let (X, Y, Z) = rgbToXYZ(r: r, g: g, b: b)
        return xyzToLab(X: X, Y: Y, Z: Z)
    }

    // ΔE2000 (implementación compacta y razonablemente correcta)
    static func deltaE2000(_ c1: Lab, _ c2: Lab) -> CGFloat {
        // Convert to doubles for numeric stability
        let L1 = Double(c1.L), a1 = Double(c1.a), b1 = Double(c1.b)
        let L2 = Double(c2.L), a2 = Double(c2.a), b2 = Double(c2.b)

        let kL = 1.0, kC = 1.0, kH = 1.0

        let C1 = sqrt(a1 * a1 + b1 * b1)
        let C2 = sqrt(a2 * a2 + b2 * b2)
        let Cbar = (C1 + C2) / 2.0

        let G = 0.5 * (1.0 - sqrt(pow(Cbar, 7.0) / (pow(Cbar, 7.0) + pow(25.0, 7.0))))
        let a1p = (1.0 + G) * a1
        let a2p = (1.0 + G) * a2

        let C1p = sqrt(a1p * a1p + b1 * b1)
        let C2p = sqrt(a2p * a2p + b2 * b2)

        func atan2deg(_ y: Double, _ x: Double) -> Double {
            var ang = atan2(y, x) * 180.0 / .pi
            if ang < 0 { ang += 360.0 }
            return ang
        }

        let h1p = (C1p < 1e-7) ? 0.0 : atan2deg(b1, a1p)
        let h2p = (C2p < 1e-7) ? 0.0 : atan2deg(b2, a2p)

        let dLp = L2 - L1
        let dCp = C2p - C1p

        var dhp: Double
        let dh = h2p - h1p
        if C1p * C2p == 0 {
            dhp = 0
        } else if abs(dh) <= 180 {
            dhp = dh
        } else if dh > 180 {
            dhp = dh - 360
        } else {
            dhp = dh + 360
        }
        let dHp = 2.0 * sqrt(C1p * C2p) * sin((dhp * .pi / 180.0) / 2.0)

        let Lbar = (L1 + L2) / 2.0
        let Cbarp = (C1p + C2p) / 2.0

        var hbarp: Double
        if C1p * C2p == 0 {
            hbarp = h1p + h2p
        } else if abs(h1p - h2p) <= 180 {
            hbarp = (h1p + h2p) / 2.0
        } else if (h1p + h2p) < 360 {
            hbarp = (h1p + h2p + 360) / 2.0
        } else {
            hbarp = (h1p + h2p - 360) / 2.0
        }

        let T = 1.0
            - 0.17 * cos((hbarp - 30) * .pi / 180.0)
            + 0.24 * cos((2 * hbarp) * .pi / 180.0)
            + 0.32 * cos((3 * hbarp + 6) * .pi / 180.0)
            - 0.20 * cos((4 * hbarp - 63) * .pi / 180.0)

        let Sl = 1.0 + (0.015 * pow(Lbar - 50.0, 2.0)) / sqrt(20.0 + pow(Lbar - 50.0, 2.0))
        let Sc = 1.0 + 0.045 * Cbarp
        let Sh = 1.0 + 0.015 * Cbarp * T

        let delTheta = 30.0 * exp(-pow((hbarp - 275.0) / 25.0, 2.0))
        let Rc = 2.0 * sqrt(pow(Cbarp, 7.0) / (pow(Cbarp, 7.0) + pow(25.0, 7.0)))
        let Rt = -Rc * sin(2.0 * delTheta * .pi / 180.0)

        let dE = sqrt(
            pow(dLp / (kL * Sl), 2.0) +
            pow(dCp / (kC * Sc), 2.0) +
            pow(dHp / (kH * Sh), 2.0) +
            Rt * (dCp / (kC * Sc)) * (dHp / (kH * Sh))
        )
        return CGFloat(dE)
    }

    // MARK: - Paleta de nombres (sRGB 0..1)
    static let referencePalette: [NamedRGB] = [
        // Neutros
        .init(name: "Negro", r: 0.02, g: 0.02, b: 0.02),
        .init(name: "Blanco", r: 0.98, g: 0.98, b: 0.98),
        .init(name: "Gris", r: 0.5, g: 0.5, b: 0.5),
        .init(name: "Gris claro", r: 0.75, g: 0.75, b: 0.75),
        .init(name: "Gris oscuro", r: 0.25, g: 0.25, b: 0.25),

        // Rojos / Naranjas / Amarillos
        .init(name: "Rojo", r: 0.90, g: 0.10, b: 0.10),
        .init(name: "Rojo oscuro", r: 0.55, g: 0.05, b: 0.05),
        .init(name: "Naranja", r: 0.95, g: 0.55, b: 0.10),
        .init(name: "Amarillo", r: 0.95, g: 0.90, b: 0.10),

        // Verdes / Cian
        .init(name: "Verde", r: 0.10, g: 0.75, b: 0.20),
        .init(name: "Verde oscuro", r: 0.05, g: 0.40, b: 0.10),
        .init(name: "Cian", r: 0.10, g: 0.80, b: 0.85),
        .init(name: "Turquesa", r: 0.18, g: 0.70, b: 0.60),

        // Azules / Violetas
        .init(name: "Azul", r: 0.10, g: 0.35, b: 0.90),
        .init(name: "Azul marino", r: 0.05, g: 0.10, b: 0.35),
        .init(name: "Índigo", r: 0.25, g: 0.20, b: 0.55),
        .init(name: "Violeta", r: 0.60, g: 0.30, b: 0.85),
        .init(name: "Magenta", r: 0.85, g: 0.20, b: 0.75),
        .init(name: "Rosa", r: 0.95, g: 0.55, b: 0.80),

        // Marrones / Beige
        .init(name: "Marrón", r: 0.45, g: 0.25, b: 0.10),
        .init(name: "Beige", r: 0.88, g: 0.80, b: 0.65)
    ]

    static func nearestNameByDE2000(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let targetLab = rgbToLab(r: r, g: g, b: b)
        var bestName = "Color"
        var bestDE: CGFloat = .greatestFiniteMagnitude

        for ref in referencePalette {
            let lab = rgbToLab(r: ref.r, g: ref.g, b: ref.b)
            let de = deltaE2000(targetLab, lab)
            if de < bestDE {
                bestDE = de
                bestName = ref.name
            }
        }
        return bestName
    }

    // MARK: - Utilidades de lectura de CGImage (RGBA8)

    // Convierte cualquier CGImage a un buffer RGBA8 contiguo seguro para lectura
    private static func normalizedRGBAData(from cgImage: CGImage) -> (data: [UInt8], bytesPerRow: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(cgImage, in: rect)
        return (data, bytesPerRow)
    }

    // Dominante robusto (legacy method kept for compatibility):
    // - ROI central (para evitar bordes/fondos)
    // - Descarta píxeles con S baja y V muy bajo/alto extremos
    // - Hue circular ponderado por S y V
    static func dominantHSV(from cgImage: CGImage,
                            roiFraction: CGFloat = 0.6,
                            minSaturation: CGFloat = 0.15,
                            minValue: CGFloat = 0.1,
                            maxValue: CGFloat = 0.98) -> HSV {

        guard let buffer = normalizedRGBAData(from: cgImage) else {
            return HSV(h: 0, s: 0, v: 0)
        }
        let bytes = buffer.data
        let bytesPerRow = buffer.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4 // RGBA

        // ROI central
        let roiW = Int(CGFloat(width) * roiFraction)
        let roiH = Int(CGFloat(height) * roiFraction)
        let startX = max(0, (width - roiW) / 2)
        let startY = max(0, (height - roiH) / 2)
        let endX = min(width, startX + roiW)
        let endY = min(height, startY + roiH)

        // Acumuladores para hue circular y ponderación
        var sumX: CGFloat = 0 // cos(h)
        var sumY: CGFloat = 0 // sin(h)
        var sumS: CGFloat = 0
        var sumV: CGFloat = 0
        var weightSum: CGFloat = 0

        // Muestreo en cuadrícula (salto adaptativo)
        let stepX = max(1, roiW / 96)
        let stepY = max(1, roiH / 96)

        for y in stride(from: startY, to: endY, by: stepY) {
            let rowBase = y * bytesPerRow
            for x in stride(from: startX, to: endX, by: stepX) {
                let offset = rowBase + x * bytesPerPixel
                if offset + 3 < bytes.count {
                    // RGBA (premultiplied last, byteOrder32Big)
                    let r = CGFloat(bytes[offset + 0]) / 255.0
                    let g = CGFloat(bytes[offset + 1]) / 255.0
                    let b = CGFloat(bytes[offset + 2]) / 255.0

                    let hsv = rgbToHSV(r: r, g: g, b: b)

                    // Filtro de calidad
                    if hsv.s < minSaturation { continue }
                    if hsv.v < minValue || hsv.v > maxValue { continue }

                    // Peso por saturación y valor (colores más saturados y bien expuestos pesan más)
                    let w = hsv.s * clamp((hsv.v - minValue) / (maxValue - minValue), 0, 1)

                    // Hue circular a radianes
                    let rad = hsv.h * .pi / 180.0
                    sumX += cos(rad) * w
                    sumY += sin(rad) * w

                    sumS += hsv.s * w
                    sumV += hsv.v * w
                    weightSum += w
                }
            }
        }

        if weightSum == 0 {
            // Fallback: muestreo simple del bitmap completo (conversión previa asegura canales)
            return simpleAverageHSV(from: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
        }

        let avgH = atan2(sumY, sumX) * 180.0 / .pi
        let hue = avgH < 0 ? avgH + 360.0 : avgH
        let sat = sumS / weightSum
        let val = sumV / weightSum

        return HSV(h: hue, s: sat, v: val)
    }

    // Fallback simple (por si el filtro deja sin pesos válidos)
    private static func simpleAverageHSV(from bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> HSV {
        let bytesPerPixel = 4
        var accumH: CGFloat = 0
        var accumS: CGFloat = 0
        var accumV: CGFloat = 0
        var count: CGFloat = 0

        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)

        for y in stride(from: 0, to: height, by: stepY) {
            let rowBase = y * bytesPerRow
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = rowBase + x * bytesPerPixel
                if offset + 3 < bytes.count {
                    let r = CGFloat(bytes[offset + 0]) / 255.0
                    let g = CGFloat(bytes[offset + 1]) / 255.0
                    let b = CGFloat(bytes[offset + 2]) / 255.0
                    let hsv = rgbToHSV(r: r, g: g, b: b)
                    accumH += hsv.h
                    accumS += hsv.s
                    accumV += hsv.v
                    count += 1
                }
            }
        }
        if count == 0 { return HSV(h: 0, s: 0, v: 0) }
        return HSV(h: accumH / count, s: accumS / count, v: accumV / count)
    }

    private static func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        return min(max(x, a), b)
    }

    // Nombre descriptivo del color (simple pero útil para UX)
    static func descriptiveName(for hsv: HSV, locale: Locale = Locale(identifier: "es")) -> String {
        let h = hsv.h
        let s = hsv.s
        let v = hsv.v

        // Tono
        let hueName: String = {
            switch h {
            case 0..<15, 345...360: return "Rojo"
            case 15..<45: return "Naranja"
            case 45..<65: return "Amarillo"
            case 65..<170: return "Verde"
            case 170..<200: return "Cian"
            case 200..<255: return "Azul"
            case 255..<290: return "Índigo"
            case 290..<345: return "Magenta"
            default: return "Gris"
            }
        }()

        // Saturación y valor para adjetivo
        let descriptor: String = {
            if v < 0.25 { return "muy oscuro" }
            if v < 0.5 { return "oscuro" }
            if v > 0.85 && s < 0.25 { return "muy claro" }
            if v > 0.75 { return "claro" }
            if s < 0.2 { return "apagado" }
            return ""
        }()

        if descriptor.isEmpty {
            return hueName
        } else {
            return "\(hueName) \(descriptor)"
        }
    }

    // Matrices 3x3 para simulación/corrección de daltonismo
    static var protanopiaMatrix: simd_float3x3 {
        simd_float3x3(rows: [
            simd_float3(0.566, 0.433, 0.0),
            simd_float3(0.558, 0.442, 0.0),
            simd_float3(0.0,   0.242, 0.758)
        ])
    }

    static var deuteranopiaMatrix: simd_float3x3 {
        simd_float3x3(rows: [
            simd_float3(0.625, 0.375, 0.0),
            simd_float3(0.7,   0.3,   0.0),
            simd_float3(0.0,   0.3,   0.7)
        ])
    }
}

