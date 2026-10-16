import Flutter
import UIKit
import AVFoundation
import AudioToolbox

public final class PlatformAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannelName = "dev.dawnmesh.intercom/audio"
    private static let eventChannelName = "dev.dawnmesh.intercom/audio_events"

    public static let sampleRate: Double = 16000.0
    public static let frameSamples: Int = 320 // 20ms @ 16kHz
    public static let bytesPerFrame: Int = frameSamples * 2 // 640 bytes

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    fileprivate var audioUnit: AudioComponentInstance?
    private var isCapturing: Bool = false
    private var isMuted: Bool = false
    private var userWantsSpeaker: Bool = true
    private var preferBuiltinMic: Bool = false
    private var currentBitrate: Int = 24000

    // 远端音频流混音队列（按发送方 ID 分流）
    private let playbackLock = NSLock()
    private final class RemoteStream {
        let decoder: UnsafeMutableRawPointer
        var jitter = DawnJitterQueue()
        init?() { guard let value = dm_decoder_create() else { return nil }; decoder = value }
        deinit { dm_decoder_free(decoder) }
    }
    private var remoteStreams = [Int: RemoteStream]()
    private var encoder: UnsafeMutableRawPointer?
    private var denoiser: UnsafeMutableRawPointer?
    private var capturePending = [Int16]()
    private var playbackPending = [Int16]()
    private var playbackOffset = 0
    private var noiseLevel = UserDefaults.standard.object(forKey: "noiseReduction") as? Int ?? 1
    private var prebuffer = 6
    private var maxFrames = 24
    private var concealmentLimit = 2
    private var captureGeneration = 0
    private var wantsCapture = false
    private var internetAudio = false
    private var routeRecovery: DispatchWorkItem?
    private var observers = [NSObjectProtocol]()

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self.stopAudioEngine() }
            else if self.wantsCapture {
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                if options.contains(.shouldResume) { self.resumeAudio() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            self.routeRecovery?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.internetAudio { self.methodChannel?.invokeMethod("internetAudioRouteChanged", arguments: nil) }
                else if self.wantsCapture { self.updateAudioRouting() }
            }
            self.routeRecovery = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.stopAudioEngine()
            if self.wantsCapture { self.resumeAudio() }
        })
    }
    deinit { routeRecovery?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func resumeAudio() {
        do { try startAudioEngine() }
        catch { eventSink?(FlutterError(code: "CAPTURE_FAILED", message: "系统中断后无法恢复音频", details: nil)) }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PlatformAudioPlugin()
        instance.setupChannels(messenger: registrar.messenger())
    }

    public func setupChannels(messenger: FlutterBinaryMessenger) {
        let mChannel = FlutterMethodChannel(name: PlatformAudioPlugin.methodChannelName, binaryMessenger: messenger)
        mChannel.setMethodCallHandler(self.handle)
        self.methodChannel = mChannel

        let eChannel = FlutterEventChannel(name: PlatformAudioPlugin.eventChannelName, binaryMessenger: messenger)
        eChannel.setStreamHandler(self)
        self.eventChannel = eChannel
    }

    public func detachChannels() {
        stopAudioEngine()
        methodChannel?.setMethodCallHandler(nil)
        methodChannel = nil
        eventChannel?.setStreamHandler(nil)
        eventChannel = nil
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - FlutterMethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCapture":
            let args = call.arguments as? [String: Any]
            currentBitrate = args?["bitrate"] as? Int ?? 24000
            internetAudio = false
            wantsCapture = true
            captureGeneration += 1
            let requestedGeneration = captureGeneration
            checkMicrophonePermission { [weak self] granted in
                guard let self = self else { return }
                guard self.wantsCapture, self.captureGeneration == requestedGeneration else {
                    result(FlutterError(code: "CANCELLED", message: "录音请求已取消", details: nil)); return
                }
                if !granted {
                    self.wantsCapture = false
                    result(FlutterError(code: "PERMISSION_DENIED", message: "缺少麦克风权限，无法开启语音对讲", details: nil))
                    return
                }
                do {
                    try self.startAudioEngine()
                    result(nil)
                } catch {
                    result(FlutterError(code: "CAPTURE_FAILED", message: "音频引擎初始化失败: \(error.localizedDescription)", details: nil))
                }
            }

        case "stopCapture":
            wantsCapture = false
            captureGeneration += 1
            stopAudioEngine()
            result(nil)

        case "setMuted":
            if let args = call.arguments as? [String: Any], let muted = args["muted"] as? Bool {
                playbackLock.lock()
                isMuted = muted
                capturePending.removeAll()
                playbackLock.unlock()
            }
            result(nil)

        case "setSpeakerphone":
            if let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool {
                userWantsSpeaker = enabled
                updateAudioRouting()
            }
            result(nil)

        case "setUseBuiltinMic":
            if let args = call.arguments as? [String: Any], let useBuiltin = args["useBuiltinMic"] as? Bool {
                preferBuiltinMic = useBuiltin
                updateAudioRouting()
            }
            result(nil)

        case "setBitrate":
            if let args = call.arguments as? [String: Any], let bitrate = args["bitrate"] as? Int {
                playbackLock.lock()
                currentBitrate = max(6000, min(64000, bitrate))
                _ = dm_encoder_bitrate(encoder, Int32(currentBitrate))
                playbackLock.unlock()
            }
            result(nil)

        case "submitRemoteFrame":
            if let args = call.arguments as? [String: Any],
               let typedData = args["data"] as? FlutterStandardTypedData {
                let data = typedData.data
                handleRemoteFrameData(data)
            }
            result(nil)

        case "removeRemoteMember":
            let args = call.arguments as? [String: Any]
            playbackLock.lock()
            if let id = args?["memberId"] as? Int { remoteStreams.removeValue(forKey: id) }
            playbackPending.removeAll(); playbackOffset = 0
            playbackLock.unlock()
            result(nil)
        case "clearRemoteMembers", "stopPlayback":
            playbackLock.lock()
            remoteStreams.removeAll(); playbackPending.removeAll(); playbackOffset = 0
            playbackLock.unlock()
            if call.method == "stopPlayback" && !wantsCapture && !internetAudio {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            result(nil)
        case "getNoiseReduction": result(noiseLevel)
        case "setNoiseReduction":
            let args = call.arguments as? [String: Any]
            playbackLock.lock()
            noiseLevel = max(0, min(2, args?["level"] as? Int ?? 1))
            UserDefaults.standard.set(noiseLevel, forKey: "noiseReduction")
            playbackLock.unlock()
            DawnMeshInternetDSP.shared().setLevel(Int32(noiseLevel))
            result(nil)
        case "startInternetNoiseReduction":
            internetAudio = true
            wantsCapture = false; stopAudioEngine()
            DawnMeshInternetDSP.shared().start(Int32(noiseLevel))
            result(nil)
        case "stopInternetNoiseReduction":
            internetAudio = false
            DawnMeshInternetDSP.shared().stop()
            result(nil)
        case "setAudioTuningProfile", "setAudioTuningParameters":
            let args = call.arguments as? [String: Any] ?? [:]
            let profile = args["profile"] as? String ?? "balanced"
            playbackLock.lock()
            prebuffer = max(1, min(15, args["prebufferFrames"] as? Int ?? (profile == "low" ? 2 : profile == "stable" ? 10 : 6)))
            maxFrames = max(prebuffer, min(32, args["maxBufferFrames"] as? Int ?? 24))
            concealmentLimit = max(0, min(3, args["maxConcealmentFrames"] as? Int ?? 2))
            for stream in remoteStreams.values {
                stream.jitter.prebuffer = prebuffer; stream.jitter.maxFrames = maxFrames
                stream.jitter.concealmentLimit = concealmentLimit
            }
            playbackLock.unlock()
            result(nil)
        case "dispose":
            detachChannels()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 权限检查

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - VoiceProcessingIO 音频引擎

    private func startAudioEngine() throws {
        guard !isCapturing else { return }
        DawnMeshInternetDSP.shared().stop()
        encoder = dm_encoder_create(Int32(currentBitrate))
        denoiser = dm_denoiser_create(16000)
        guard encoder != nil, denoiser != nil else {
            stopAudioEngine()
            throw NSError(domain: "DawnAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Opus 初始化失败"])
        }
        var success = false
        defer { if !success { stopAudioEngine() } }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setPreferredSampleRate(PlatformAudioPlugin.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "PlatformAudioPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "VoiceProcessingIO 未找到"])
        }

        var unit: AudioComponentInstance?
        let statusNew = AudioComponentInstanceNew(comp, &unit)
        guard statusNew == noErr, let audioUnit = unit else {
            throw NSError(domain: "PlatformAudioPlugin", code: Int(statusNew), userInfo: [NSLocalizedDescriptionKey: "创建 AudioUnit 失败: \(statusNew)"])
        }
        self.audioUnit = audioUnit

        // 启用 Input (录音: Element 1) 与 Output (播放: Element 0)
        var one: UInt32 = 1
        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, UInt32(MemoryLayout<UInt32>.size)))
        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, UInt32(MemoryLayout<UInt32>.size)))

        // 音频流格式定义：16kHz, 单声道, 16-bit 线性 PCM
        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: PlatformAudioPlugin.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))

        // 录音输入回调
        var inputCallback = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))

        // 播放渲染回调
        var renderCallback = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try checkAudioStatus(AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))

        try checkAudioStatus(AudioUnitInitialize(audioUnit))
        try checkAudioStatus(AudioOutputUnitStart(audioUnit))
        isCapturing = true
        success = true

        updateAudioRouting()
    }

    private func checkAudioStatus(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: "DawnAudio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "AudioUnit 错误 \(status)"]) }
    }
    private func stopAudioEngine() {
        isCapturing = false
        captureGeneration += 1
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        playbackLock.lock()
        dm_encoder_free(encoder); encoder = nil
        dm_denoiser_free(denoiser); denoiser = nil
        remoteStreams.removeAll(); capturePending.removeAll(); playbackPending.removeAll(); playbackOffset = 0
        playbackLock.unlock()
    }

    private func updateAudioRouting() {
        let session = AVAudioSession.sharedInstance()
        do {
            if userWantsSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }

            if preferBuiltinMic {
                if let builtin = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtin)
                }
            } else {
                try session.setPreferredInput(nil)
                if let headset = session.availableInputs?.first(where: {
                    $0.portType == .headsetMic || $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
                }) {
                    try session.setPreferredInput(headset)
                }
            }
        } catch {
            print("[DawnAudio] 音频路由切换失败: \(error)")
        }
    }

    // MARK: - 远端数据入队与混音

    private func handleRemoteFrameData(_ data: Data) {
        guard data.count >= 6, data[0] == 1 else { return }
        let sender = Int(data[1])
        let sequence = UInt16(data[2]) << 8 | UInt16(data[3])
        let length = Int(data[4]) << 8 | Int(data[5])
        guard length > 0, length <= 512, data.count == length + 6 else { return }
        playbackLock.lock()
        defer { playbackLock.unlock() }
        if remoteStreams[sender] == nil {
            guard remoteStreams.count < 16, let stream = RemoteStream() else { return }
            stream.jitter.prebuffer = prebuffer; stream.jitter.maxFrames = maxFrames
            stream.jitter.concealmentLimit = concealmentLimit
            remoteStreams[sender] = stream
        }
        remoteStreams[sender]?.jitter.append(sequence: sequence, packet: data.subdata(in: 6..<data.count), now: ProcessInfo.processInfo.systemUptime)
    }

    fileprivate func processCapturedPcm(samples: [Int16]) {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard isCapturing, !isMuted, let encoder = encoder else { capturePending.removeAll(); return }
        capturePending.append(contentsOf: samples)
        while capturePending.count >= 320 {
            var frame = Array(capturePending.prefix(320))
            capturePending.removeFirst(320)
            frame.withUnsafeMutableBufferPointer { _ = dm_denoise(denoiser, $0.baseAddress, 320, Int32(noiseLevel)) }
            let energy = frame.reduce(0.0) { $0 + Double($1) * Double($1) }
            let level = min(1.0, sqrt(energy / 320.0) / 32768.0)
            var encoded = [UInt8](repeating: 0, count: 512)
            let length = frame.withUnsafeBufferPointer { pcm in
                encoded.withUnsafeMutableBufferPointer { dm_encode(encoder, pcm.baseAddress, 320, $0.baseAddress, 512) }
            }
            guard length > 0 else { continue }
            let packet = Data(encoded.prefix(Int(length)))
            let generation = captureGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isCapturing, !self.isMuted, self.captureGeneration == generation else { return }
                self.eventSink?(["data": FlutterStandardTypedData(bytes: packet), "level": level])
            }
        }
    }

    fileprivate func providePlaybackPcm(into buffer: UnsafeMutablePointer<Int16>, sampleCount: Int) {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        for index in 0..<sampleCount {
            if playbackOffset >= playbackPending.count {
                var mixed = [Int32](repeating: 0, count: 320)
                for stream in remoteStreams.values {
                    guard let packet = stream.jitter.pop() else { continue }
                    var pcm = [Int16](repeating: 0, count: 320)
                    let decoded = pcm.withUnsafeMutableBufferPointer { out in
                        packet.withUnsafeBytes { raw in
                            dm_decode(stream.decoder, raw.bindMemory(to: UInt8.self).baseAddress, Int32(packet.count), out.baseAddress, 320)
                        }
                    }
                    if decoded == 320 { for i in 0..<320 { mixed[i] += Int32(pcm[i]) } }
                }
                playbackPending = mixed.map { Int16(clamping: $0) }
                playbackOffset = 0
            }
            buffer[index] = playbackPending[playbackOffset]
            playbackOffset += 1
        }
    }

}

// MARK: - AudioUnit 回调 C 桥接

private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let plugin = Unmanaged<PlatformAudioPlugin>.fromOpaque(inRefCon).takeUnretainedValue()

    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 2,
            mData: nil
        )
    )

    let bufferSize = Int(inNumberFrames) * 2
    let dataPtr = malloc(bufferSize)
    defer { free(dataPtr) }
    bufferList.mBuffers.mData = dataPtr

    guard let unit = plugin.audioUnit else {
        return noErr
    }

    let status = AudioUnitRender(
        unit,
        ioActionFlags,
        inTimeStamp,
        1,
        inNumberFrames,
        &bufferList
    )

    if status == noErr, let rawData = bufferList.mBuffers.mData {
        let sampleCount = Int(inNumberFrames)
        let ptr = rawData.bindMemory(to: Int16.self, capacity: sampleCount)
        var samples = [Int16](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = ptr[i]
        }
        plugin.processCapturedPcm(samples: samples)
    }

    return noErr
}

private func audioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let plugin = Unmanaged<PlatformAudioPlugin>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let bufferList = ioData else { return noErr }
    let buffer = bufferList.pointee.mBuffers
    guard let destPtr = buffer.mData?.bindMemory(to: Int16.self, capacity: Int(inNumberFrames)) else {
        return noErr
    }

    plugin.providePlaybackPcm(into: destPtr, sampleCount: Int(inNumberFrames))
    return noErr
}
