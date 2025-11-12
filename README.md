

⸻

🧠 Visuaid

Asistente visual inteligente para detección de color, texto y formas — Proyecto Final de Técnicas de Interpretación Avanzadas

⸻

📱 Descripción general

Visuaid es una aplicación desarrollada en SwiftUI que utiliza procesamiento de imágenes en tiempo real para asistir a personas con discapacidades visuales y demostrar los algoritmos estudiados en el curso.
Combina visión por computadora, accesibilidad y teoría del color, integrando los siguientes temas vistos en los cuadernos .ipynb y PDFs:
	•	Modelos de color (RGB, HSV, Lab)
	•	Detección y corrección de daltonismo (pseudocolor)
	•	Threshold simple y adaptativo
	•	Detección de bordes (Sobel, Laplaciano, Canny)
	•	Detección de contornos (Suzuki) y componentes conectados
	•	Reconocimiento de texto (OCR) y lectura por voz

⸻

🎯 Objetivo del proyecto

Desarrollar una herramienta educativa y funcional que aplique los fundamentos de procesamiento digital de imágenes para mejorar la percepción visual y el acceso a la información, especialmente para usuarios con daltonismo o baja visión.

⸻

🧩 Funciones principales

🟢 1. Color
	•	Detección del color dominante en tiempo real (modelo HSV).
	•	Conversión RGB ↔ HSV ↔ Lab.
	•	Lectura de color por voz (AVSpeechSynthesizer).
	•	Filtros de corrección de daltonismo (Protanopía / Deuteranopía).
	•	Umbralización Global y Adaptativa para resaltar regiones.
	•	Detección de contornos con VNDetectContoursRequest.

📘 Basado en los temas de Modelos de Color (7_modelosColor.pdf), Threshold (6_Threshold.pdf) y Contornos (8_contornos_componentes_conectados.pdf).

⸻

🔵 2. Texto
	•	Detección y lectura de texto (OCR con Vision API).
	•	Limpieza de imagen mediante umbral adaptativo y detección de bordes.
	•	Conversión de texto detectado a voz en tiempo real.

📘 Basado en Thresholding y Edge Detection (6_Threshold.pdf y 5_edgeDetection.pdf).

⸻

🟡 3. ColorSeguro
	•	Reetiquetado de colores confusos para daltonismo.
	•	Conversión RGB → Lab para comparar diferencias ΔE*.
	•	Aplicación de pseudocolor con CIColorMatrix o CIColorCube.
	•	Comparador visual: original ↔ corregido.

📘 Basado en Pseudocolor y Modelos de Color (7_modelosColor.pdf).

⸻

🔺 4. Formas
	•	Detección de bordes y contornos geométricos (Canny + Suzuki).
	•	Clasificación de figuras (círculo, triángulo, cuadrado).
	•	Cálculo de momentos e identificación de centroides.
	•	Dibujo de bounding boxes sobre las figuras detectadas.

📘 Basado en Contornos y Componentes Conectados (8_contornos_componentes_conectados.pdf).

⸻

⚙️ 5. Ajustes
	•	Control global de lectura por voz.
	•	Configuración de sensibilidad de umbral y brillo.
	•	Selección del filtro de daltonismo por defecto.
	•	Alternar visualización de contornos o modos de color.

⸻

🧬 Estructura del Proyecto

Visuaid/
├── VisuaidApp.swift
├── MainTabView.swift
│
├── Modules/
│   ├── ColorDetection/
│   │   ├── ColorDetectionView.swift
│   │   ├── ColorDetectionViewModel.swift
│   │   └── Helpers/
│   │       ├── ColorUtilities.swift
│   │       └── ImageProcessor.swift
│   │
│   ├── TextReader/
│   │   ├── TextReaderView.swift
│   │   └── TextReaderViewModel.swift
│   │
│   ├── ColorSafe/
│   │   ├── ColorSafeView.swift
│   │   └── ColorSafeViewModel.swift
│   │
│   ├── ShapeDetection/
│   │   ├── ShapeDetectionView.swift
│   │   └── ShapeDetectionViewModel.swift
│   │
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
│
├── Camera/
│   ├── CameraService.swift
│   └── CameraView.swift
│
├── Audio/
│   └── ColorSpeaker.swift
│
├── Processing/
│   ├── ContourOverlay.swift
│   └── ImageProcessor.swift
│
└── README.md


⸻

🧪 Fundamento teórico (conexión con los .ipynb)

Tema	Archivo del curso	Aplicación en Visuaid
Modelos de color	7_modelosColor.pdf	HSV para detección de color, Lab para corrección
Threshold simple/adaptativo	6_Threshold.pdf	Limpieza y segmentación de texto e imágenes
Detección de bordes	5_edgeDetection.pdf	Realce visual y detección de formas
Contornos y CCA	8_contornos_componentes_conectados.pdf	Detección de señales y figuras geométricas
Pseudocolor	7_modelosColor.pdf	Reasignación perceptual de colores confusos
OCR	(Integración adicional con Vision)	Lectura de texto mediante reconocimiento óptico


⸻

⚙️ Instalación y uso

🔧 Requisitos
	•	macOS 13+
	•	Xcode 15+
	•	iPhone con iOS 16 o superior (el simulador no tiene cámara)

▶️ Ejecución
	1.	Clona o descarga el proyecto:

git clone https://github.com/tuusuario/Visuaid.git


	2.	Abre Visuaid.xcodeproj en Xcode.
	3.	En Info.plist, verifica los permisos:
	•	NSCameraUsageDescription
	•	NSMicrophoneUsageDescription
	4.	Ejecuta el proyecto en un dispositivo real (⌘R).
	5.	Permite acceso a cámara y micrófono al iniciarse.

⸻

🧠 Cómo funciona internamente
	•	El flujo de cámara usa AVFoundation para capturar frames en formato BGRA.
	•	Cada frame se convierte a CIImage para aplicar los filtros de procesamiento.
	•	El análisis (color, bordes, contornos, texto) se realiza con Core Image y Vision.
	•	Los resultados se muestran en vivo con SwiftUI y se narran con AVSpeechSynthesizer.

⸻

📚 Referencias del curso
	•	Dra. Karina Ruby Pérez-Daniel, Técnicas de Interpretación Avanzadas, Universidad Panamericana (2025).
	•	Modelos de Color, Thresholding, Edge Detection, Contornos y Componentes Conectados (material PDF y cuadernos .ipynb).
	•	OpenCV + Core Image equivalencias teóricas aplicadas a iOS.

⸻

💬 Créditos

Proyecto desarrollado por:
	•	Juan Pablo Orihuela Araiza, Rodrigo López Moreno, Itzayana Partida Ibarra, Aranza Romo Lima
	•	Universidad Panamericana — Ingeniería en Animación y Videojuegos
	•	Curso: Técnicas de Interpretación Avanzadas (Otoño 2025)

⸻


