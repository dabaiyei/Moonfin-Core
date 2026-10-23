import AVFoundation
import CoreImage
import Flutter

/// AVPlayer composition keeps the original playback clock, audio and PiP.
/// Aether's sample-buffer/software path has no public frame filter hook.
@MainActor
final class FacebetterVideoBeauty {
    static let shared = FacebetterVideoBeauty()
    private let processor = FacebetterFrameProcessor()
    private var channel: FlutterMethodChannel?
    private weak var player: AVPlayer?
    private weak var item: AVPlayerItem?
    private var observation: NSKeyValueObservation?
    private var externalObservation: NSKeyValueObservation?
    private var composition: AVVideoComposition?
    private var generation = 0
    private var enabled = false
    private var status = "waiting"

    func register(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "moonfin/beauty_control", binaryMessenger: messenger)
        channel?.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case "setBeautyPreferences":
                let args = call.arguments as? [String: Any] ?? [:]
                let next = args["enabled"] as? Bool ?? false
                let changed = next != self.enabled
                self.enabled = next
                let credentialsChanged = self.processor.update(args)
                if changed || credentialsChanged || self.composition == nil { self.refresh() }
                result(["status": self.status])
            case "getBeautyStatus":
                result(["status": self.status])
            default: result(FlutterMethodNotImplemented)
            }
        }
        processor.onStatus = { [weak self] value in
            Task { @MainActor in
                guard let self, self.enabled, self.composition != nil else { return }
                self.status = value
            }
        }
    }

    func bind(_ player: AVPlayer?) {
        self.player = player
        observation = player?.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        externalObservation = player?.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        if player == nil { refresh() }
    }

    private func removeComposition() {
        if let composition, item?.videoComposition === composition {
            item?.videoComposition = nil
        }
        composition = nil
    }

    private func refresh() {
        generation += 1
        let token = generation
        removeComposition()
        item = player?.currentItem
        guard enabled else { status = "disabled"; return }
        guard processor.configured else { status = "missingLicense"; return }
        guard player?.isExternalPlaybackActive != true else { status = "bypassPlaybackPath"; return }
        guard let item else { status = player == nil ? "bypassPlaybackPath" : "waiting"; return }
        guard item.videoComposition == nil else { status = "bypassPlaybackPath"; return }
        status = "waiting"
        Task { [weak self, weak item] in
            guard let self, let item else { return }
            do {
                let asset = item.asset
                let composable = try await asset.load(.isComposable)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard self.generation == token, self.item === item else { return }
                guard composable, let track = tracks.first else {
                    self.status = "bypassPlaybackPath"; return
                }
                let size = try await track.load(.naturalSize)
                let fps = try await track.load(.nominalFrameRate)
                let descriptions = try await track.load(.formatDescriptions)
                guard self.generation == token, self.item === item else { return }
                for description in descriptions {
                    let extensions = (CMFormatDescriptionGetExtensions(description) as NSDictionary?) ?? NSDictionary()
                    let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String ?? ""
                    let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String ?? ""
                    let subtype = CMFormatDescriptionGetMediaSubType(description)
                    if transfer.contains("2084") || transfer.contains("HLG") ||
                        primaries.contains("2020") || subtype == 0x64766831 || subtype == 0x64766865 {
                        self.status = "bypassHdr"; return
                    }
                }
                let long = max(abs(size.width), abs(size.height))
                let short = min(abs(size.width), abs(size.height))
                guard long > 0, short > 0, fps.isFinite, fps > 0 else { return }
                guard long <= 1920, short <= 1080 else { self.status = "bypassResolution"; return }
                guard fps <= 60.1, fps <= 30.1 || (long <= 1280 && short <= 720) else {
                    self.status = "bypassFrameRate"; return
                }
                let processor = self.processor
                let composition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
                    let source = request.sourceImage
                    let output = processor.process(source) ?? source
                    request.finish(with: output, context: nil)
                })
                guard self.generation == token, self.item === item, self.enabled else { return }
                self.composition = composition
                item.videoComposition = composition
                self.status = "initializing"
            } catch {
                if self.generation == token { self.status = "bypassPlaybackPath" }
            }
        }
    }
}

/// The SDK owns its GL context. CPU frames cross the boundary, so Aether's
/// Metal/AVFoundation contexts never become the SDK's current GL context.
private final class FacebetterFrameProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "moonfin.facebetter.frames")
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let configLock = NSLock()
    private var config: [String: String]
    private var engine: FBBeautyEffectEngine?
    private var values: [String: Float] = [:]
    private var enabled = false
    private var ready = false
    private var failed = false
    private var basicOnly = false
    private var started = Date.distantPast
    private var attempt = 0
    var onStatus: (@Sendable (String) -> Void)?

    init() {
        if let url = Bundle.main.url(forResource: "FacebetterConfig", withExtension: "plist"),
            let dictionary = NSDictionary(contentsOf: url) as? [String: String] {
            config = dictionary
        } else { config = [:] }
    }

    private func credentials() -> [String: String] {
        configLock.lock()
        defer { configLock.unlock() }
        return config
    }

    var configured: Bool {
        let values = credentials()
        return !(values["LICENSE_TOKEN"] ?? "").isEmpty ||
            (!(values["APP_ID"] ?? "").isEmpty && !(values["APP_KEY"] ?? "").isEmpty)
    }

    func update(_ args: [String: Any]) -> Bool {
        var credentialsChanged = false
        if let incoming = args["license"] as? [String: String] {
            let next = ["LICENSE_TOKEN": incoming["licenseToken"] ?? "",
                        "APP_ID": incoming["appId"] ?? "", "APP_KEY": incoming["appKey"] ?? ""]
            configLock.lock()
            credentialsChanged = config != next
            config = next
            configLock.unlock()
        }
        let resetEngine = credentialsChanged
        let nextEnabled = args["enabled"] as? Bool ?? false
        var next: [String: Float] = [:]
        for key in ["smoothing", "whitening", "rosiness", "sharpening", "faceThin", "eyeSize"] {
            let number = (args[key] as? NSNumber)?.floatValue ?? 0
            next[key] = number.isFinite ? min(1, max(0, number)) : 0
        }
        let captured = next
        queue.async {
            self.enabled = nextEnabled
            self.values = captured
            if !nextEnabled || resetEngine {
                self.attempt += 1
                self.engine = nil
                self.ready = false
                self.failed = false
            } else if self.ready { self.applyValues() }
        }
        return credentialsChanged
    }

    private func applyValues() {
        guard let engine else { return }
        engine.setBeautySkinOnly(true)
        engine.setSmoothing(values["smoothing"] ?? 0)
        engine.setWhitening(values["whitening"] ?? 0)
        engine.setRosiness(values["rosiness"] ?? 0)
        engine.setSharpening(values["sharpening"] ?? 0)
        let face = engine.setReshape(.faceThin, intensity: values["faceThin"] ?? 0)
        let eyes = engine.setReshape(.eyeSize, intensity: values["eyeSize"] ?? 0)
        basicOnly = (face != 0 && (values["faceThin"] ?? 0) > 0) ||
            (eyes != 0 && (values["eyeSize"] ?? 0) > 0)
    }

    func process(_ image: CIImage) -> CIImage? {
        queue.sync {
            guard enabled, configured else { return nil }
            guard !failed else { onStatus?("failed"); return nil }
            if engine == nil {
                let config = credentials()
                let cfg = FBEngineConfig()
                cfg.licenseToken = config["LICENSE_TOKEN"] ?? ""
                cfg.appId = config["APP_ID"] ?? ""
                cfg.appKey = config["APP_KEY"] ?? ""
                cfg.externalContext = false
                engine = FBBeautyEffectEngine.createEngine(with: cfg)
                attempt += 1
                let currentAttempt = attempt
                let callbacks = FBEngineCallbacks()
                callbacks.onEngineEvent = { [weak self] code, _ in
                    guard let self else { return }
                    // Callbacks may be synchronous inside processImage. Never
                    // take the processing queue synchronously from a callback.
                    self.queue.async {
                        guard self.attempt == currentAttempt else { return }
                        switch code {
                        case .initializationComplete: self.ready = true; self.applyValues()
                        case .initializationFailed, .licenseValidationFailed:
                            self.failed = true; self.ready = false
                        default: break
                        }
                    }
                }
                engine?.setCallbacks(callbacks)
                started = Date()
            }
            guard let engine else { failed = true; onStatus?("failed"); return nil }
            let bounds = image.extent.integral
            guard bounds.width.isFinite, bounds.height.isFinite,
                bounds.width > 0, bounds.height > 0, max(bounds.width, bounds.height) <= 1920,
                min(bounds.width, bounds.height) <= 1080 else { onStatus?("bypassResolution"); return nil }
            let width = Int(bounds.width), height = Int(bounds.height)
            var inputBuffer: CVPixelBuffer?
            let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                attrs, &inputBuffer) == kCVReturnSuccess, let inputBuffer else { return nil }
            context.render(image.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)),
                to: inputBuffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
            CVPixelBufferLockBaseAddress(inputBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(inputBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(inputBuffer) else { return nil }
            guard let input = FBImageFrame.create(withBGRA: base.assumingMemoryBound(to: UInt8.self),
                width: Int32(width), height: Int32(height), stride: Int32(CVPixelBufferGetBytesPerRow(inputBuffer))) else { return nil }
            input.type = .video
            let processed = engine.processImage(input)
            guard ready else {
                if Date().timeIntervalSince(started) > 15 { failed = true; onStatus?("failed") }
                else { onStatus?("initializing") }
                return nil
            }
            guard let bgra = processed?.convert(.BGRA), let data = bgra.data(),
                Int(bgra.width) == width, Int(bgra.height) == height, Int(bgra.stride) >= width * 4 else {
                onStatus?("failed"); return nil
            }
            // Own the output after the SDK reuses its frame. Use the same
            // pixel-buffer convention as the CIContext input conversion.
            var outputBuffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                attrs, &outputBuffer) == kCVReturnSuccess, let outputBuffer else { return nil }
            CVPixelBufferLockBaseAddress(outputBuffer, [])
            guard let destination = CVPixelBufferGetBaseAddress(outputBuffer) else {
                CVPixelBufferUnlockBaseAddress(outputBuffer, []); return nil
            }
            let stride = CVPixelBufferGetBytesPerRow(outputBuffer)
            for row in 0..<height {
                memcpy(destination.advanced(by: row * stride), data.advanced(by: row * Int(bgra.stride)), width * 4)
            }
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            let result = CIImage(cvPixelBuffer: outputBuffer, options: [.colorSpace: colorSpace])
            onStatus?(basicOnly ? "readyBasicOnly" : "ready")
            return result.transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
        }
    }
}
