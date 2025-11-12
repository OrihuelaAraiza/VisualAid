//
//  ImageProcessor.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//
//  Procesamiento de imagen en tiempo real (CIContext GPU).
//  Incluye threshold global/adaptativo (6_Threshold.pdf), Sobel/Canny (5_edgeDetection.pdf),
//  segmentación por color y matrices 3x3 para daltonismo.
//  Detección de contornos con Vision (Suzuki) del 8_contornos_componentes_conectados.pdf
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import AVFoundation
import simd

@MainActor
final class ImageProcessor: ObservableObject {
    // Configuración de procesamiento
    @Published var thresholdMode: ThresholdMode = .global
    @Published var edgeMode: EdgeMode = .none
    @Published var processingMode: ProcessingMode = .original
    @Published var colorBlindness: ColorBlindnessMode = .none
    @Published var globalThreshold: Float = 0.5 // 0...1
    @Published var adaptiveC: Float = 0.05      // Constante C del método adaptativo
    @Published var showContours: Bool = false

    // Resultados
    @Published private(set) var outputCGImage: CGImage?
    @Published private(set) var contours: [VNContour] = []
    @Published private(set) var lastDominantName: String = ""

    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let request = VNDetectContoursRequest()

    init() {
        // CIContext con GPU
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 512
    }

    // Entrada: CVPixelBuffer desde la cámara
    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)

        // Pipeline configurable
        let processed = applyPipeline(to: ciImage)

        // Render a CGImage
        if let cg = renderCGImage(from: processed) {
            self.outputCGImage = cg

            // Color dominante
            let hsv = ColorUtilities.dominantHSV(from: cg)
            let name = ColorUtilities.descriptiveName(for: hsv)
            self.lastDominantName = name

            // Contornos con Vision si está activo
            if showContours {
                detectContours(on: cg)
            } else {
                self.contours = []
            }
        }
    }

    // MARK: - Pipeline

    private func applyPipeline(to input: CIImage) -> CIImage {
        var image = input

        switch processingMode {
        case .original:
            break
        case .grayscale:
            image = toGrayscale(image)
        case .threshold:
            image = toGrayscale(image)
            image = applyThreshold(image)
        case .edges:
            image = toGrayscale(image)
            image = applyEdges(image)
        case .colorSegmentation:
            image = colorSegmentation(image)
        }

        // Daltonismo / Pseudocolor
        if colorBlindness != .none {
            image = applyColorBlindnessFilter(image, mode: colorBlindness)
        }

        return image
    }

    // MARK: - Grayscale

    private func toGrayscale(_ image: CIImage) -> CIImage {
        // Luma Rec. 709
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: 0.2126, y: 0.2126, z: 0.2126, w: 0)
        filter.gVector = CIVector(x: 0.7152, y: 0.7152, z: 0.7152, w: 0)
        filter.bVector = CIVector(x: 0.0722, y: 0.0722, z: 0.0722, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    // MARK: - Threshold (6_Threshold.pdf)

    private func applyThreshold(_ image: CIImage) -> CIImage {
        switch thresholdMode {
        case .global:
            // gray > threshold
            let t = globalThreshold
            let thresholdFilter = CIFilter.colorClamp()
            thresholdFilter.inputImage = image
            thresholdFilter.minComponents = CIVector(x: CGFloat(t), y: CGFloat(t), z: CGFloat(t), w: 0)
            thresholdFilter.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            let clamped = thresholdFilter.outputImage ?? image

            // Binarizar: (clamped - t) > 0 ? 1 : 0
            let binarize = CIFilter.colorMatrix()
            binarize.inputImage = clamped
            binarize.rVector = CIVector(x: 1000, y: 0, z: 0, w: -CGFloat(1000 * t))
            binarize.gVector = CIVector(x: 0, y: 1000, z: 0, w: -CGFloat(1000 * t))
            binarize.bVector = CIVector(x: 0, y: 0, z: 1000, w: -CGFloat(1000 * t))
            binarize.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return binarize.outputImage ?? image

        case .adaptive:
            // gray > (gaussianBlur(gray) - C)
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image
            blur.radius = 3
            let blurred = blur.outputImage ?? image

            let c = adaptiveC
            // image - (blurred - C) > 0
            let subtract = CIFilter.blendWithAlphaMask()
            // Aproximamos con una resta usando colorMatrix para sumar C
            let addC = CIFilter.colorMatrix()
            addC.inputImage = blurred
            addC.rVector = CIVector(x: 1, y: 0, z: 0, w: CGFloat(c))
            addC.gVector = CIVector(x: 0, y: 1, z: 0, w: CGFloat(c))
            addC.bVector = CIVector(x: 0, y: 0, z: 1, w: CGFloat(c))
            addC.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            let blurredPlusC = addC.outputImage ?? blurred

            // Usamos un filtro de comparación aproximado: image > blurredPlusC
            let comparator = CIFilter.maximumCompositing()
            comparator.inputImage = image
            comparator.backgroundImage = blurredPlusC
            let maxed = comparator.outputImage ?? image

            // Binarizar (aproximación)
            let binarize = CIFilter.colorMatrix()
            binarize.inputImage = maxed
            binarize.rVector = CIVector(x: 1000, y: 0, z: 0, w: 0)
            binarize.gVector = CIVector(x: 0, y: 1000, z: 0, w: 0)
            binarize.bVector = CIVector(x: 0, y: 0, z: 1000, w: 0)
            binarize.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return binarize.outputImage ?? image
        }
    }

    // MARK: - Bordes (5_edgeDetection.pdf)

    private func applyEdges(_ image: CIImage) -> CIImage {
        switch edgeMode {
        case .none:
            return image
        case .sobel:
            // Sobel con kernels
            let gx = CIFilter.convolution3X3()
            gx.inputImage = image
            gx.bias = 0
            gx.weights = CIVector(values: [
                -1, 0, 1,
                -2, 0, 2,
                -1, 0, 1
            ], count: 9)

            let gy = CIFilter.convolution3X3()
            gy.inputImage = image
            gy.bias = 0
            gy.weights = CIVector(values: [
                 1,  2,  1,
                 0,  0,  0,
                -1, -2, -1
            ], count: 9)

            guard let ix = gx.outputImage, let iy = gy.outputImage else { return image }

            // Magnitud aproximada |G| = |Gx| + |Gy|
            let absX = ix.applyingFilter("CIAbsoluteDifference", parameters: ["inputImage2": CIImage(color: .black).cropped(to: ix.extent)])
            let absY = iy.applyingFilter("CIAbsoluteDifference", parameters: ["inputImage2": CIImage(color: .black).cropped(to: iy.extent)])
            let combined = absX.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: absY])

            return combined
        case .canny:
            // Aproximación de Canny: suavizado + gradiente + umbrales
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image
            blur.radius = 1.5
            let blurred = blur.outputImage ?? image

            // Gradiente (Sobel)
            let sobel = applyEdges(blurred)
            // Umbral doble aproximado
            let low: CGFloat = 0.1
            let high: CGFloat = 0.3

            let lowClamp = sobel.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: low, y: low, z: low, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            let highClamp = sobel.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: high, y: high, z: high, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            let edges = highClamp.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: lowClamp])
            return edges
        }
    }

    // MARK: - Segmentación por color (7_modelosColor.pdf)

    private func colorSegmentation(_ image: CIImage) -> CIImage {
        // Ejemplo: potenciar rojos mediante umbral en HSV aproximado
        // Implementación simple usando color controls + matrix
        let increasedSat = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.5,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 1.0
        ])
        return increasedSat
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

    // MARK: - Vision Contours (8_contornos_componentes_conectados.pdf)

    private func detectContours(on cgImage: CGImage) {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            if let obs = request.results?.first {
                self.contours = obs.topLevelContours
            } else {
                self.contours = []
            }
        } catch {
            self.contours = []
        }
    }

    // MARK: - Render

    private func renderCGImage(from image: CIImage) -> CGImage? {
        let rect = image.extent.integral
        return ciContext.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace)
    }
}
