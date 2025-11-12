//
//  ColorUtilities.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Conversiones RGB↔HSV↔Lab y naming de color dominante.
//  Basado en conceptos de 7_modelosColor.pdf
//

import CoreGraphics
import CoreImage
import SwiftUI

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

struct ColorUtilities {

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

    // Aproximación sRGB D65 → XYZ → Lab
    static func rgbToLab(r: CGFloat, g: CGFloat, b: CGFloat) -> Lab {
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

        // Normaliza por blanco de referencia D65
        let Xn: CGFloat = 0.95047
        let Yn: CGFloat = 1.00000
        let Zn: CGFloat = 1.08883

        func f(_ t: CGFloat) -> CGFloat {
            let delta: CGFloat = 6.0 / 29.0
            return (t > pow(delta, 3)) ? pow(t, 1.0/3.0) : (t / (3 * pow(delta, 2)) + 4.0/29.0)
        }

        let fx = f(X / Xn)
        let fy = f(Y / Yn)
        let fz = f(Z / Zn)

        let L = (116 * fy) - 16
        let a = 500 * (fx - fy)
        let b = 200 * (fy - fz)
        return Lab(L: L, a: a, b: b)
    }

    // Estimar color dominante en HSV usando un muestreo simple del bitmap (rápido)
    static func dominantHSV(from cgImage: CGImage) -> HSV {
        // Muestreo en cuadrícula para rendimiento
        let width = cgImage.width
        let height = cgImage.height
        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)

        guard let data = cgImage.dataProvider?.data as Data? else {
            return HSV(h: 0, s: 0, v: 0)
        }
        let bytes = [UInt8](data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var accumH: CGFloat = 0
        var accumS: CGFloat = 0
        var accumV: CGFloat = 0
        var count: CGFloat = 0

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 3 < bytes.count {
                    let b = CGFloat(bytes[offset + 0]) / 255.0
                    let g = CGFloat(bytes[offset + 1]) / 255.0
                    let r = CGFloat(bytes[offset + 2]) / 255.0
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
    // Valores de ejemplo comunes en literatura; ajustables.
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
