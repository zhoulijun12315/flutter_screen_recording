import Flutter
import UIKit
import ReplayKit
import Photos

public class SwiftFlutterScreenRecordingPlugin: NSObject, FlutterPlugin {
    
let recorder = RPScreenRecorder.shared()

var videoOutputURL : URL?
var videoWriter : AVAssetWriter?

var audioInput:AVAssetWriterInput!
var videoWriterInput : AVAssetWriterInput?
var nameVideo: String = ""
var recordAudio: Bool = false;
var myResult: FlutterResult?
let screenSize = UIScreen.main.bounds
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_screen_recording", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterScreenRecordingPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

    if(call.method == "startRecordScreen"){
         myResult = result
         let args = call.arguments as? Dictionary<String, Any>

         self.recordAudio = (args?["audio"] as? Bool)!
         self.nameVideo = (args?["name"] as? String)!+".mp4"
         startRecording()

    }else if(call.method == "stopRecordScreen"){
        if(videoWriter != nil){
            stopRecording()
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            result(String(documentsPath.appendingPathComponent(nameVideo)))
        }
         result("")
    }
  }


    @objc func startRecording() {
        print("Starting recording...")
        
        // 确保之前的录制已经完全停止
        if videoWriter != nil {
            stopRecording()
        }

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        self.videoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent(nameVideo))
        print("Video will be saved to: \(self.videoOutputURL?.path ?? "")")

        do {
            try FileManager.default.removeItem(at: videoOutputURL!)
        } catch {}

        do {
            try videoWriter = AVAssetWriter(outputURL: videoOutputURL!, fileType: AVFileType.mp4)
        } catch let writerError as NSError {
            print("Error creating writer: \(writerError)")
            myResult?(false)
            return
        }

        if #available(iOS 11.0, *) {
            let codec = AVVideoCodecH264
            
            // 获取当前设备方向
            let orientation = UIDevice.current.orientation
            let isLandscape = orientation.isLandscape
            
            // 获取屏幕的实际分辨率
            let nativeWidth = UIScreen.main.nativeBounds.width
            let nativeHeight = UIScreen.main.nativeBounds.height
            
            // 根据方向设置正确的宽高
            let videoWidth = isLandscape ? max(nativeWidth, nativeHeight) : min(nativeWidth, nativeHeight)
            let videoHeight = isLandscape ? min(nativeWidth, nativeHeight) : max(nativeWidth, nativeHeight)
            
            print("Screen native bounds: \(UIScreen.main.nativeBounds)")
            print("Recording with orientation: \(orientation.rawValue), dimensions: \(videoWidth)x\(videoHeight)")
            
            // 视频压缩设置
            let compressionProperties: [String: Any] = [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAverageBitRateKey: 80_000_000,
                AVVideoMaxKeyFrameIntervalKey: 10,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoQualityKey: 1.0,
                AVVideoAllowFrameReorderingKey: false
            ]
            
            let videoSettings: [String : Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,  // 改用 Aspect 而不是 AspectFill
                AVVideoCompressionPropertiesKey: compressionProperties
            ]

            // 创建视频写入器
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            // 根据方向设置变换
            if isLandscape {
                var transform = CGAffineTransform.identity
                
                // 设置旋转
                let rotationAngle = orientation == .landscapeLeft ? 
                    -CGFloat.pi*2 :     // landscapeLeft: -360度
                    CGFloat.pi*2        // landscapeRight: 向右旋转360度
                transform = transform.rotated(by: rotationAngle)
                
                // 设置平移以确保内容居中
                if orientation == .landscapeLeft {
                    transform = transform.translatedBy(x: 0, y: -videoHeight)
                } else {
                    transform = transform.translatedBy(x: 0, y: videoHeight)
                }
                
                videoWriterInput?.transform = transform
                
                // 添加方向元数据
                if let writer = videoWriter {
                    let orientationMetadata = AVMutableMetadataItem()
                    orientationMetadata.keySpace = AVMetadataKeySpace.common
                    orientationMetadata.key = "orientation" as NSString
                    orientationMetadata.value = orientation == .landscapeLeft ? "0" as NSString : "180" as NSString
                    writer.metadata = [orientationMetadata]
                }
            }
            
            // 设置视频写入器的其他属性
            if let writer = videoWriter {
                writer.movieTimeScale = CMTimeScale(600)
                writer.shouldOptimizeForNetworkUse = true
                
                // 添加视频方向标记
                let orientationMetadata = AVMutableMetadataItem()
                orientationMetadata.keySpace = AVMetadataKeySpace.common
                orientationMetadata.key = "orientation" as NSString
                orientationMetadata.value = isLandscape ? "90" as NSString : "0" as NSString
                writer.metadata = [orientationMetadata]
            }
            
            // 添加像素缓冲适配器，使用更高质量的设置
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64ARGB,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: attributes
            )
            
            if let input = videoWriterInput {
                videoWriter?.add(input)
            }

            // 音频设置
            if(recordAudio){
                let audioSettings: [String : Any] = [
                    AVNumberOfChannelsKey: 2,
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,                // 提高采样率
                    AVEncoderBitRateKey: 192000,          // 192kbps 音频比特率
                    AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
                ]
                
                audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                videoWriter?.add(audioInput)
            }

            RPScreenRecorder.shared().isMicrophoneEnabled = recordAudio

            var isWritingStarted = false
            let writingQueue = DispatchQueue(label: "com.recording.writing")

            RPScreenRecorder.shared().startCapture(handler: { [weak self] (cmSampleBuffer, rpSampleType, error) in
                guard let self = self else { return }
                
                if let error = error {
                    print("Capture error: \(error.localizedDescription)")
                    return
                }

                writingQueue.async {
                    switch rpSampleType {
                    case RPSampleBufferType.video:
                        if !isWritingStarted {
                            isWritingStarted = true
                            if self.videoWriter?.status != .writing {
                                self.videoWriter?.startWriting()
                                self.videoWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(cmSampleBuffer))
                                print("Started writing session")
                                DispatchQueue.main.async {
                                    self.myResult?(true)
                                }
                            }
                        }
                        
                        if self.videoWriter?.status == .writing,
                           let input = self.videoWriterInput,
                           input.isReadyForMoreMediaData {
                            if !input.append(cmSampleBuffer) {
                                print("Failed to write video frame")
                            }
                        }
                        
                    case RPSampleBufferType.audioMic:
                        if self.recordAudio,
                           self.videoWriter?.status == .writing,
                           self.audioInput.isReadyForMoreMediaData {
                            if !self.audioInput.append(cmSampleBuffer) {
                                print("Failed to write audio frame")
                            }
                        }
                        
                    @unknown default:
                        break
                    }
                }
            }) { [weak self] (error) in
                if let error = error {
                    print("Failed to start capture: \(error.localizedDescription)")
                    self?.myResult?(false)
                }
            }
        }
    }

    @objc func stopRecording() {
        print("Stopping recording...")
        
        let group = DispatchGroup()
        group.enter()
        
        if #available(iOS 11.0, *) {
            RPScreenRecorder.shared().stopCapture { [weak self] (error) in
                guard let self = self else {
                    group.leave()
                    return
                }
                
                if let error = error {
                    print("Stop capture error: \(error.localizedDescription)")
                    group.leave()
                    return
                }
                
                print("Capture stopped, finalizing video...")
                
                self.videoWriterInput?.markAsFinished()
                if self.recordAudio {
                    self.audioInput?.markAsFinished()
                }
                
                self.videoWriter?.finishWriting { [weak self] in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    
                    if let error = self.videoWriter?.error {
                        print("Error finishing video: \(error.localizedDescription)")
                    } else {
                        print("Video writing finished")
                        // 移除保存到相册的代码，只打印路径
                        if let url = self.videoOutputURL {
                            print("Video saved to: \(url.path)")
                        }
                    }
                    group.leave()
                }
            }
        }
        
        // 等待录制完成
        _ = group.wait(timeout: .now() + 5.0)
    }
    
}
