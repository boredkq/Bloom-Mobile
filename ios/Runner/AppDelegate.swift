import AVFoundation
import Flutter
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// I keep a reference: this is the picker's delegate, and ARC would free it
  /// just as the dialog shows.
  private var files: FilesChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Nightcore.install()
    NowPlayingLike.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomFiles") {
      files = FilesChannel(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomNightcore") {
      Nightcore.register(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomLike") {
      NowPlayingLike.register(registrar: registrar)
    }
  }
}

/// The favorite star on the lock screen, over `bloom/like`.
///
/// iOS only lets the system `likeCommand` in there: a star left of "previous",
/// filled by `isActive`. I can't draw a heart, the system picks the icon.
///
/// The plugin has no API for it and turns it off on every
/// `activateCommandCenter`, so I swizzle that method and turn the star back on.
/// If the method gets renamed, the swap just doesn't happen and there's no
/// star; nothing here can crash.
///
/// Untested on a device: CI only builds this.
enum NowPlayingLike {
  /// Whether the playing track is a favorite and the button's title, as last
  /// sent from Dart.
  static var active = false
  static var title = "Like"
  private static var channel: FlutterMethodChannel?
  private static var installed = false

  static func install() {
    guard !installed else { return }
    installed = true
    if let cls = NSClassFromString("AudioServicePlugin"),
      let original = class_getInstanceMethod(cls, NSSelectorFromString("activateCommandCenter")),
      let ours = class_getInstanceMethod(
        NSObject.self,
        #selector(NSObject.bloom_activateCommandCenter)
      ),
      // I add my method to the plugin's class and exchange there, otherwise the
      // swap would hit NSObject's implementation.
      class_addMethod(
        cls,
        #selector(NSObject.bloom_activateCommandCenter),
        method_getImplementation(ours),
        method_getTypeEncoding(ours)
      ),
      let added = class_getInstanceMethod(cls, #selector(NSObject.bloom_activateCommandCenter))
    {
      method_exchangeImplementations(original, added)
    }
    // One target is enough: the plugin never removes targets from
    // `likeCommand`.
    MPRemoteCommandCenter.shared().likeCommand.addTarget { _ in
      channel?.invokeMethod("toggle", arguments: nil)
      return .success
    }
  }

  static func register(registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bloom/like",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      active = args["active"] as? Bool ?? false
      title = args["title"] as? String ?? title
      apply()
      result(nil)
    }
    self.channel = channel
  }

  static func apply() {
    let command = MPRemoteCommandCenter.shared().likeCommand
    command.isEnabled = true
    command.isActive = active
    command.localizedTitle = title
    command.localizedShortTitle = title
  }
}

extension NSObject {
  /// After the exchange, calling `bloom_…` here runs the plugin's original
  /// method.
  @objc dynamic func bloom_activateCommandCenter() {
    bloom_activateCommandCenter()
    NowPlayingLike.apply()
  }
}

/// Nightcore on iOS, over `bloom/nightcore`.
///
/// just_audio can't `setPitch` on iOS and gives every item
/// `AVAudioTimePitchAlgorithmTimeDomain`, which holds the pitch at any speed. A
/// pitch that follows the tempo is `varispeed`, and the plugin doesn't expose
/// it. So I swizzle two setters: the item's algorithm, to force `varispeed`
/// while nightcore is on, and the player's rate, to remember the player and fix
/// the current item right away rather than from the next track.
///
/// If the plugin stops calling the algorithm setter, nightcore just stops
/// working; nothing here can crash.
///
/// Untested on a device: CI only builds this.
enum Nightcore {
  /// Whether it's on. All on the main thread: the plugin and the channel alike.
  static var on = false
  /// just_audio's player, which I learn from the first rate set.
  static weak var player: AVPlayer?
  private static var installed = false

  static func install() {
    guard !installed else { return }
    installed = true
    swap(
      AVPlayerItem.self,
      #selector(setter: AVPlayerItem.audioTimePitchAlgorithm),
      #selector(AVPlayerItem.bloom_setAudioTimePitchAlgorithm(_:))
    )
    swap(
      AVPlayer.self,
      #selector(setter: AVPlayer.rate),
      #selector(AVPlayer.bloom_setRate(_:))
    )
  }

  static func register(registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bloom/nightcore",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      Nightcore.apply(call.arguments as? Bool ?? false)
      result(nil)
    }
  }

  /// Switches on the fly: re-sets the algorithm on every queued item through
  /// the swizzled setter, which picks `varispeed` or `timeDomain` itself.
  private static func apply(_ value: Bool) {
    guard value != on else { return }
    on = value
    guard let player = player else { return }
    let items = (player as? AVQueuePlayer)?.items() ?? [player.currentItem].compactMap { $0 }
    for item in items {
      item.audioTimePitchAlgorithm = .timeDomain
    }
    // Re-setting the rate is the surest way to apply the algorithm to the
    // playing item, and it's safe: the plugin doesn't observe `rate`.
    if player.rate > 0 {
      player.rate = player.rate
    }
  }

  private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard
      let a = class_getInstanceMethod(cls, original),
      let b = class_getInstanceMethod(cls, replacement)
    else { return }
    method_exchangeImplementations(a, b)
  }
}

extension AVPlayerItem {
  /// After the exchange, calling `bloom_…` here runs the original setter.
  @objc dynamic func bloom_setAudioTimePitchAlgorithm(_ value: AVAudioTimePitchAlgorithm) {
    bloom_setAudioTimePitchAlgorithm(Nightcore.on ? .varispeed : value)
  }
}

extension AVPlayer {
  /// After the exchange, calling `bloom_…` here runs the original setter.
  @objc dynamic func bloom_setRate(_ value: Float) {
    Nightcore.player = self
    if Nightcore.on, value > 0, let item = currentItem,
      item.audioTimePitchAlgorithm != .varispeed
    {
      item.audioTimePitchAlgorithm = .varispeed
    }
    bloom_setRate(value)
  }
}

/// System file dialogs through `UIDocumentPicker`, the iOS side of
/// `bloom/files`: the presets file and adding own tracks.
///
/// Saving goes through a temp file, since the export picker hands out a file,
/// not a string. Cancelling isn't an error: I answer `false`/`nil`.
///
/// iOS has no "in place" mode: a file from another sandbox lives under a
/// security scope, and getting back to it after a restart takes a bookmark I'd
/// have to store and refresh. So the picker uses `asCopy: true` and a track is
/// always copied in, whatever the setting says.
///
/// It stays in this file on purpose: a new file would have to be added to the
/// Xcode project by hand, and I can't check an iOS build locally.
///
/// Untested on a device: CI only builds this.
class FilesChannel: NSObject, UIDocumentPickerDelegate {

  /// What the closing picker was opened for.
  private enum Kind {
    case save
    case open
    case audio
  }

  private var pending: FlutterResult?
  private var kind = Kind.save
  /// The temp export file, removed when the picker closes.
  private var exported: URL?

  /// Where own tracks and their covers go, and which are already added.
  private var tracksDir = ""
  private var coversDir = ""
  private var known = Set<String>()
  /// Keeps apart the names of covers written in the same second.
  private var coverSeq = 0

  init(registrar: FlutterPluginRegistrar) {
    super.init()
    let channel = FlutterMethodChannel(
      name: "bloom/files",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "saveText":
        self.saveText(
          filename: args["filename"] as? String ?? "bloom.bloompresets",
          content: args["content"] as? String ?? "",
          result: result
        )
      case "openText":
        self.openText(result: result)
      case "pickAudio":
        self.pickAudio(
          tracksDir: args["tracksDir"] as? String ?? "",
          coversDir: args["coversDir"] as? String ?? "",
          known: args["known"] as? [String] ?? [],
          result: result
        )
      case "shareFile":
        // To the system share sheet. No provider needed: the file is in the
        // app's sandbox.
        self.shareFile(
          path: args["path"] as? String ?? "",
          text: args["text"] as? String,
          result: result
        )
      case "releaseAudio":
        // Nothing to release: on iOS the file is always my copy, and Dart
        // deletes it.
        result(nil)
      case "diskSpace":
        // The phone's storage: the denominator of the ring on the storage
        // screen.
        self.diskSpace(result: result)
      case "appInfo":
        // The build version for the About row.
        let info = Bundle.main.infoDictionary
        result([
          "version": info?["CFBundleShortVersionString"] as? String ?? "",
          "build": info?["CFBundleVersion"] as? String ?? "",
          // The name in the computer's device list (since iOS 16 just "iPhone"
          // without a special entitlement).
          "device": UIDevice.current.name,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Total and free space on the app's volume; `nil` when the system doesn't
  /// answer, and the screen then shows no share.
  private func diskSpace(result: @escaping FlutterResult) {
    guard
      let attrs = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
      ),
      let total = (attrs[.systemSize] as? NSNumber)?.int64Value,
      let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
    else {
      result(nil)
      return
    }
    result(["total": total, "free": free])
  }

  /// Shows `UIActivityViewController` for a ready file.
  ///
  /// I answer right after showing it: what gets picked in the sheet isn't my
  /// business, and cancelling looks the same as sending.
  ///
  /// `popoverPresentationController` is required: on iPad the sheet is a
  /// popover and crashes without an anchor.
  private func shareFile(path: String, text: String?, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path), let top = topController() else {
      result(FlutterError(code: "share", message: "nothing to send", details: nil))
      return
    }
    var items: [Any] = [url]
    if let text = text, !text.isEmpty { items.append(text) }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(
        x: top.view.bounds.midX,
        y: top.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
    result(true)
  }

  private func topController() -> UIViewController? {
    var top = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func saveText(filename: String, content: String, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "a file dialog is already open", details: nil))
      return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
      return
    }
    pending = result
    kind = .save
    exported = url
    let picker = UIDocumentPickerViewController(forExporting: [url])
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func openText(result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "a file dialog is already open", details: nil))
      return
    }
    pending = result
    kind = .open
    // `.bloompresets` has no registered type, so I allow any file and Dart
    // checks the format when parsing.
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func pickAudio(
    tracksDir: String,
    coversDir: String,
    known: [String],
    result: @escaping FlutterResult
  ) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "a file dialog is already open", details: nil))
      return
    }
    pending = result
    kind = .audio
    self.tracksDir = tracksDir
    self.coversDir = coversDir
    self.known = Set(known)
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [UTType.audio],
      asCopy: true
    )
    picker.allowsMultipleSelection = true
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func finish(_ value: Any?) {
    guard let result = pending else { return }
    pending = nil
    if let url = exported {
      try? FileManager.default.removeItem(at: url)
      exported = nil
    }
    result(value)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    switch kind {
    case .save:
      finish(true)
    case .open:
      guard let url = urls.first else {
        finish(nil)
        return
      }
      // A file from another sandbox can only be read under a security scope.
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      finish(try? String(contentsOf: url, encoding: .utf8))
    case .audio:
      if urls.isEmpty {
        finish(nil)
        return
      }
      // Copying and reading tags hit the disk, and this is the main thread the
      // app draws on.
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        let entries = urls.compactMap { self.importAudio($0) }
        DispatchQueue.main.async { self.finish(entries) }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(kind == .save ? false : nil)
  }

  /// One picked file to a track entry; `nil` if it's already in the library or
  /// unreadable.
  ///
  /// `asCopy: true` already put it in the temp folder, so I move it in before
  /// the system clears tmp.
  private func importAudio(_ source: URL) -> [String: Any]? {
    let name = source.lastPathComponent
    let attrs = try? FileManager.default.attributesOfItem(atPath: source.path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    let key = "\(name)|\(size)"
    // The key also drops duplicates within one batch.
    if known.contains(key) { return nil }
    known.insert(key)

    let dir = URL(fileURLWithPath: tracksDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = uniqueFile(dir: dir, name: safeName(name))
    do {
      try FileManager.default.moveItem(at: source, to: dest)
    } catch {
      // The move failed, so I try a copy: tmp may be on another volume.
      guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else {
        known.remove(key)
        return nil
      }
    }

    let asset = AVURLAsset(url: dest)
    var entry: [String: Any] = [
      "key": key,
      "name": name,
      "size": size,
      "file": dest.lastPathComponent,
      "durationMs": Int(CMTimeGetSeconds(asset.duration) * 1000),
    ]
    for item in asset.commonMetadata {
      switch item.commonKey {
      case .some(.commonKeyTitle):
        entry["title"] = item.stringValue
      case .some(.commonKeyArtist), .some(.commonKeyAuthor):
        if entry["artist"] == nil { entry["artist"] = item.stringValue }
      case .some(.commonKeyAlbumName):
        entry["album"] = item.stringValue
      case .some(.commonKeyCreationDate):
        entry["year"] = item.stringValue
      case .some(.commonKeyArtwork):
        if let data = item.dataValue, let cover = saveCover(data) {
          entry["cover"] = cover
        }
      default:
        break
      }
    }
    return entry
  }

  /// Saves an embedded cover to the covers folder; `nil` if the write failed.
  private func saveCover(_ data: Data) -> String? {
    let dir = URL(fileURLWithPath: coversDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // The extension is only nominal: Flutter recognizes the picture by its
    // bytes (tags almost always hold JPEG).
    let name = "lt_\(Int(Date().timeIntervalSince1970))_\(coverSeq).jpg"
    coverSeq += 1
    do {
      try data.write(to: dir.appendingPathComponent(name))
      return name
    } catch {
      return nil
    }
  }

  /// `Song.mp3`, `Song (2).mp3`, `Song (3).mp3`…
  private func uniqueFile(dir: URL, name: String) -> URL {
    var candidate = dir.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var n = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      let next = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
      candidate = dir.appendingPathComponent(next)
      n += 1
    }
    return candidate
  }

  private func safeName(_ name: String) -> String {
    let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let clean = name.components(separatedBy: bad).joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)
    return clean.isEmpty ? "audio" : String(clean.prefix(120))
  }
}
