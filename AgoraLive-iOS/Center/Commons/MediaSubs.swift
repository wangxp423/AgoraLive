//
//  MediaSubs.swift
//  AGECenter
//
//  Created by CavanSu on 2019/7/9.
//  Copyright © 2019 Agora. All rights reserved.
//

import AgoraRtcKit
import Foundation
import AGECamera

class Capture: NSObject {
    private var agoraKit: AgoraRtcEngineKit {
        return MediaKit.rtcKit
    }
    
    private var cameraSession: AGESingleCamera?
    
    private(set) var video: AGESwitch = .off {
        didSet {
            guard oldValue != video else {
                return
            }
            
            parent.checkChannelProfile()
            
            #if (!arch(i386) && !arch(x86_64))
            if parent.channelStatus == .out {
                switch video {
                case .on:  agoraKit.startPreview()
                case .off: agoraKit.stopPreview()
                }
            }
            agoraKit.enableLocalVideo(video.boolValue)
            #endif
        }
    }
    
    var audio: AGESwitch = .off {
        didSet {
            guard oldValue != audio else {
                return
            }
            agoraKit.enableLocalAudio(audio.boolValue)
            parent.checkChannelProfile()
        }
    }
    
    func video(_ action: AGESwitch) throws {
        if cameraSession == nil {
            #if (!arch(i386) && !arch(x86_64))
            cameraSession = try AGESingleCamera(position: cameraPostion)
            cameraSession?.delegate = parent
            #endif
        }
        
        switch action {
        case .on:
            #if (!arch(i386) && !arch(x86_64))
            agoraKit.setVideoSource(parent)
            #endif
            video = .on
            #if (!arch(i386) && !arch(x86_64))
            let configuration = AGESingleCamera.CaptureConfiguration()
            try cameraSession?.start(work: .capture(configuration: configuration))
            #endif
        case .off:
            #if (!arch(i386) && !arch(x86_64))
            cameraSession?.stopWork()
            #endif
            video = .off
            #if (!arch(i386) && !arch(x86_64))
            agoraKit.setVideoSource(nil)
            #endif
        }
    }
    
    func videoResolution(_ resolution: AVCaptureSession.Preset) {
        cameraSession?.set(resolution: resolution)
    }
    
    #if os(iOS)
    var cameraPostion: AGECamera.Position {
        get {
        
            return cameraSession?.position ?? .front
        }
        
        set {
            try? cameraSession?.switchPosition(newValue)
        }
    }
    #endif
    
    private var parent: MediaKit
    
    init(parent: MediaKit) {
        self.parent = parent
    }
    
    #if os(iOS)
    func switchCamera() throws {
        guard let camera = cameraSession else {
            throw AGEError(type: .valueNil("camera session"))
        }
         
        try camera.switchPosition(camera.position.toggle)
    }
    #endif
}

class Player: NSObject, AGELogBase {
    var logTube: LogTube {
        get {
            return ALCenter.shared().centerProvideLogTubeHelper()
        }
        set {
        }
    }
    
    enum Event {
        case audioOutputRouting(((AudioOutputRouting) -> Void)? = nil)
    }
    
    typealias Priority = AgoraUserPriority
    typealias RenderMode = AgoraVideoRenderMode
    typealias VideoStreamType = AgoraVideoStreamType
    
    private lazy var observers = [NSObject: Event]()
    private(set) var isLocalAudioLoop = false
    
    var audioRoute: AudioOutputRouting = .default {
        didSet {
            for (_, event) in observers {
                switch event {
                case .audioOutputRouting(let callback):
                    if let tCallback = callback {
                        tCallback(audioRoute)
                    }
                }
            }
        }
    }
    
    var mixFileAudioFinish: (() -> Void)? = nil
    
    private var agoraKit: AgoraRtcEngineKit {
        return MediaKit.rtcKit
    }
    
    func startRenderLocalVideoStream(id: Int, view: UIView, isMirror: Bool = false) {
        log(info: "render local video stream", extra: "id: \(id), view frame: \(view.frame)")
        let canvas = AgoraRtcVideoCanvas(streamId: id, view: view)
        canvas.mirrorMode = isMirror ? .enabled : .disabled
        agoraKit.setupLocalVideo(canvas)
    }
    
    func startRenderRemoteVideoStream(id: Int, view: UIView) {
        log(info: "start render remote video stream", extra: "id: \(id), view frame: \(view.frame)")
        let canvas = AgoraRtcVideoCanvas(streamId: id, view: view)
        agoraKit.setupRemoteVideo(canvas)
    }
    
    func stopRenderRemoteVideoStream(id: Int) {
        log(info: "stop render remote video stream", extra: "id: \(id)")
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = UInt(id)
        canvas.view = nil
        agoraKit.setupRemoteVideo(canvas)
    }
    
    func renderRemoteVideoStream(id: Int, superResolution action: AGESwitch) {
        agoraKit.enableRemoteSuperResolution(UInt(id), enabled: action.boolValue)
    }
    
    func setRemoteVideoStream(id: Int, type: VideoStreamType) {
        agoraKit.setRemoteVideoStream(UInt(id), type: type)
    }
    
    func setRemoteVideoStream(id: Int, renderMode: RenderMode) {
        agoraKit.setRemoteRenderMode(UInt(id), mode: renderMode)
    }
    
    func render(priority: Priority, remoteVideoStream id: Int) {
        agoraKit.setRemoteUserPriority(UInt(id), type: priority)
    }
    
    func render(_ action: AGESwitch, remoteVideoStream id: Int) {
        agoraKit.muteRemoteVideoStream(UInt(id), mute: action.boolValue)
    }
    
    func startMixingFileAudio(url: String, finish: (() -> Void)? = nil) {
        self.mixFileAudioFinish = finish
        agoraKit.startAudioMixing(url, loopback: false, replace: false, cycle: 1)
    }
    
    func pauseMixFileAudio() {
        agoraKit.pauseAudioMixing()
    }
    
    func resumeMixFileAudio() {
        agoraKit.resumeAudioMixing()
    }
    
    func localInputAudioLoop(_ action: AGESwitch) {
        agoraKit.enable(inEarMonitoring: action.boolValue)
        isLocalAudioLoop = action.boolValue
    }
    
    func addEvent(_ event: Event, observer: NSObject) {
        self.observers[observer] = event
    }
    
    func removeObserver(_ observer: NSObject) {
        self.observers.removeValue(forKey: observer)
    }
}

// MARK: Log
private extension Player {
    func log(info: String, extra: String? = nil, funcName: String = #function) {
        let className = Player.self
        logOutputInfo(info, extra: extra, className: className, funcName: funcName)
    }
    
    func log(warning: String, extra: String? = nil, funcName: String = #function) {
        let className = Player.self
        logOutputWarning(warning, extra: extra, className: className, funcName: funcName)
    }
    
    func log(error: Error, extra: String? = nil, funcName: String = #function) {
        let className = Player.self
        logOutputError(error, extra: extra, className: className, funcName: funcName)
    }
}

enum VirtualAppearance {
    case none, girl, dog
    
    var image: UIImage {
        get {
            switch self {
            case .girl: return UIImage(named: "portrait-girl")!
            case .dog:  return UIImage(named: "portrait-dog")!
            case .none: fatalError()
            }
        }
    }
    
    var item: String {
        get {
            switch self {
            case .girl: return "girl"
            case .dog:  return "hashiqi"
            case .none: return "noitem"
            }
        }
    }
    
    static func item(_ item: String) -> VirtualAppearance {
        switch item {
        case "girl":    return VirtualAppearance.girl
        case "hashiqi": return VirtualAppearance.dog
        default:        return VirtualAppearance.none
        }
    }
}

class VideoEnhancement: FUClient , AGELogBase {
    private(set) var beauty: AGESwitch = .off
    private(set) var appearance: VirtualAppearance = .none
    
    var logTube: LogTube {
        get {
            return ALCenter.shared().centerProvideLogTubeHelper()
        }
        set {
        }
    }
    
    func beauty(_ action: AGESwitch, success: Completion = nil, fail: Completion = nil) {
        if beauty == action {
            if let success = success {
                success()
            }
            return
        }
        
        switch action {
        case .on:
            loadFilter(success: { [unowned self] in
                self.beauty = .on
                if let success = success {
                    success()
                }
                
                self.log(info: "loadFilter success")
            }) { [unowned self] (error) in
                self.beauty = .off
                if let fail = fail {
                    fail()
                }
                
                self.log(error: error, extra: "load filter")
            }
        case .off:
            self.beauty = .off
        }
    }
    
    func virtualAppearance(_ appearance: VirtualAppearance, success: Completion = nil, fail: Completion = nil) {
        switch appearance {
        case .girl, .dog:
            loadBackgroud(success: { [unowned self] in
                self.loadAnimoji(appearance.item, success: { [unowned self] in
                    self.appearance = appearance
                    if let success = success {
                        success()
                    }
                    
                    self.log(info: "loadAnimoji success", extra: "appearance: \(appearance.item)")
                }) { (error) in
                    if let fail = fail {
                        fail()
                    }
                    
                    self.log(error: error, extra: "load background")
                }
            }) { (error) in
                if let fail = fail {
                    fail()
                }
                
                self.log(error: error, extra: "load virtual appearance")
            }
        case .none:
            self.appearance = .none
        }
    }
    
    func reset() {
        beauty = .off
        appearance = .none
        destoryAllItems()
    }
}

// MARK: Log
private extension VideoEnhancement {
    func log(info: String, extra: String? = nil, funcName: String = #function) {
        let className = VideoEnhancement.self
        logOutputInfo(info, extra: extra, className: className, funcName: funcName)
    }
    
    func log(warning: String, extra: String? = nil, funcName: String = #function) {
        let className = VideoEnhancement.self
        logOutputWarning(warning, extra: extra, className: className, funcName: funcName)
    }
    
    func log(error: Error, extra: String? = nil, funcName: String = #function) {
        let className = VideoEnhancement.self
        logOutputError(error, extra: extra, className: className, funcName: funcName)
    }
}
