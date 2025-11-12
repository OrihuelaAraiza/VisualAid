//
//  CameraService.swift
//  Visuaid
//
//  Created by JP on 11/11/25.
//
//  Captura de cámara con AVFoundation y entrega de frames CVPixelBuffer en tiempo real.
//

import AVFoundation
import CoreVideo
import UIKit
import Combine

@MainActor
final class CameraService: NSObject, ObservableObject {
    enum CameraError: Error {
        case unauthorized
        case configurationFailed
        case cannotAddInput
        case cannotAddOutput
    }

    @Published private(set) var isRunning = false
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraService.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()

    // Entrega de frames en tiempo real
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure() async throws {
        // Permisos
        let status = await AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.unauthorized }
        } else if status == .denied || status == .restricted {
            throw CameraError.unauthorized
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Input cámara trasera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        // Output BGRA
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let outputQueue = DispatchQueue(label: "CameraService.video.output")
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }
        session.addOutput(videoOutput)

        // Orientación retrato y sin espejo para trasera
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
            // Alinea el device orientation con la conexión si hace falta
            if connection.isVideoRotationAngleSupported(0) {
                // No rotamos adicionalmente; confiar en .portrait
            }
        }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor in self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Asegura que la conexión permanezca en retrato
        if connection.isVideoOrientationSupported, connection.videoOrientation != .portrait {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported, connection.isVideoMirrored {
            connection.isVideoMirrored = false
        }
        onSampleBuffer?(sampleBuffer)
    }
}

