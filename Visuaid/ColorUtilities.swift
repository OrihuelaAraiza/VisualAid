//
//  ColorUtilities.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Conversiones RGB↔HSV↔Lab y naming de color dominante.
//  Mejora: cálculo robusto de color dominante con ROI, ponderación y hue circular.
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

    // Convierte cualquier CGImage a un buffer RGBA8 contiguo seguro para lectura
    private static func normalizedRGBAData(from cgImage: CGImage) -> (data: [UInt8], bytesPerRow: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

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

    // Dominante robusto:
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
                    // alpha = bytes[offset + 3] (no usado)

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

