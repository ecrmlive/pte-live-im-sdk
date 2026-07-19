import UIKit
import AVFoundation
import Photos
import QuickLook
import MapKit
import CoreLocation
import PteIMSDK

/** Full-screen image preview. Subclass to add watermarks, analytics, or a custom toolbar. */
@MainActor
open class PteIMUIImagePreviewController: UIViewController {
  private let imageView = UIImageView()
  private let remoteImageURL: URL?
  private var previewImage: UIImage?

  public init(image: UIImage? = nil, remoteImageURL: URL? = nil, title: String? = nil) {
    self.previewImage = image
    self.remoteImageURL = remoteImageURL
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }
  required public init?(coder: NSCoder) { nil }

  open override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    imageView.image = previewImage
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: view.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    let close = makeCloseButton()
    view.addSubview(close)
    NSLayoutConstraint.activate([
      close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)
    ])
    imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closePreview)))
    imageView.isUserInteractionEnabled = true
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(saveImage(_:)))
    imageView.addGestureRecognizer(longPress)
    loadRemoteImageIfNeeded()
  }

  open func makeCloseButton() -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
    button.tintColor = .white
    button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    button.layer.cornerRadius = 22
    button.addTarget(self, action: #selector(closePreview), for: .touchUpInside)
    return button
  }

  @objc open func closePreview() { dismiss(animated: true) }
  @objc open func saveImage(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
        guard status == .authorized || status == .limited else { return }
        Task { @MainActor [weak self] in self?.saveCurrentImage() }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { [weak self] status in
        guard status == .authorized else { return }
        Task { @MainActor [weak self] in self?.saveCurrentImage() }
      }
    }
  }

  private func saveCurrentImage() {
    guard let previewImage else { return }
    UIImageWriteToSavedPhotosAlbum(previewImage, nil, nil, nil)
  }

  private func loadRemoteImageIfNeeded() {
    guard let url = remoteImageURL, url.scheme == "https" || url.scheme == "http" else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let image = data.flatMap(UIImage.init(data:)) else { return }
      Task { @MainActor [weak self] in
        self?.previewImage = image
        self?.imageView.image = image
      }
    }.resume()
  }
}

/** Native AVPlayer-backed video page with tap play/pause, close and a seek bar. */
@MainActor
open class PteIMUIVideoPreviewController: UIViewController {
  private let videoURL: URL?
  private let placeholderImage: UIImage?
  private let playerContainer = UIView()
  private let placeholderView = UIImageView()
  private let playButton = UIButton(type: .system)
  private let progress = UISlider()
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var periodicTimeObserver: Any?
  private var duration: Double = 0
  private let playbackIdentifier = "video-preview-\(UUID().uuidString)"

  public init(videoURL: URL?, placeholderImage: UIImage? = nil, title: String? = nil) {
    self.videoURL = videoURL
    self.placeholderImage = placeholderImage
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }
  required public init?(coder: NSCoder) { nil }

  open override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    playerContainer.backgroundColor = UIColor(white: 0.07, alpha: 1)
    playerContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerContainer)
    NSLayoutConstraint.activate([
      playerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor), playerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      playerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), playerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ])
    placeholderView.image = placeholderImage
    placeholderView.contentMode = .scaleAspectFit
    placeholderView.translatesAutoresizingMaskIntoConstraints = false
    playerContainer.addSubview(placeholderView)
    NSLayoutConstraint.activate([
      placeholderView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor), placeholderView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
      placeholderView.topAnchor.constraint(equalTo: playerContainer.topAnchor), placeholderView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor)
    ])
    configurePlaybackControls()
    configurePlayer()
  }
  open override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); playerLayer?.frame = playerContainer.bounds }
  open override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || navigationController?.isBeingDismissed == true { removeTimeObserver(); PteIMUIMediaPlayback.shared.release(identifier: playbackIdentifier) }
  }

  private func configurePlaybackControls() {
    playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
    playButton.tintColor = .white
    playButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    playButton.layer.borderWidth = 1
    playButton.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
    playButton.layer.cornerRadius = 23
    playButton.translatesAutoresizingMaskIntoConstraints = false
    playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    playerContainer.addSubview(playButton)
    NSLayoutConstraint.activate([
      playButton.centerXAnchor.constraint(equalTo: playerContainer.centerXAnchor), playButton.centerYAnchor.constraint(equalTo: playerContainer.centerYAnchor),
      playButton.widthAnchor.constraint(equalToConstant: 46), playButton.heightAnchor.constraint(equalToConstant: 46)
    ])
    let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
    playerContainer.addGestureRecognizer(tap)
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
    close.tintColor = .white; close.backgroundColor = UIColor.black.withAlphaComponent(0.35); close.layer.cornerRadius = 22
    close.translatesAutoresizingMaskIntoConstraints = false
    close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    view.addSubview(close)
    NSLayoutConstraint.activate([
      close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12), close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)
    ])
    progress.minimumValue = 0; progress.maximumValue = 1; progress.minimumTrackTintColor = .white; progress.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
    progress.translatesAutoresizingMaskIntoConstraints = false
    progress.addTarget(self, action: #selector(progressChanged), for: .valueChanged)
    view.addSubview(progress)
    NSLayoutConstraint.activate([
      progress.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20), progress.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      progress.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
    ])
  }

  private func configurePlayer() {
    guard let videoURL else { return }
    let player = AVPlayer(url: videoURL)
    self.player = player
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    playerContainer.layer.insertSublayer(layer, below: placeholderView.layer)
    playerLayer = layer
    periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
      Task { @MainActor [weak self] in self?.updateProgress(time) }
    }
  }

  private func updateProgress(_ time: CMTime) {
    let itemDuration = player?.currentItem?.duration.seconds ?? 0
    guard itemDuration.isFinite, itemDuration > 0 else { return }
    duration = itemDuration
    progress.value = Float(time.seconds / itemDuration)
  }
  private func removeTimeObserver() {
    guard let observer = periodicTimeObserver else { return }
    player?.removeTimeObserver(observer)
    periodicTimeObserver = nil
  }

  @objc open func togglePlayback() {
    guard let player else { return }
    if player.timeControlStatus == .playing {
      player.pause(); playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
    } else {
      PteIMUIMediaPlayback.shared.activateVideo(identifier: playbackIdentifier, player: player)
      player.play(); placeholderView.isHidden = true; playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
    }
  }
  @objc private func progressChanged() {
    guard duration > 0 else { return }
    player?.seek(to: CMTime(seconds: duration * Double(progress.value), preferredTimescale: 600))
  }
}

/** QuickLook-backed file preview. Long press exports a copy through the Files app. */
@MainActor
open class PteIMUIFilePreviewController: UIViewController, QLPreviewControllerDataSource {
  private let sourceURL: URL
  private var localURL: URL?
  private let loading = UIActivityIndicatorView(style: .large)
  private var quickLook: QLPreviewController?

  public init(fileURL: URL, title: String? = nil) {
    self.sourceURL = fileURL
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }
  required public init?(coder: NSCoder) { nil }

  open override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    loading.translatesAutoresizingMaskIntoConstraints = false; loading.startAnimating(); view.addSubview(loading)
    NSLayoutConstraint.activate([loading.centerXAnchor.constraint(equalTo: view.centerXAnchor), loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
    close.translatesAutoresizingMaskIntoConstraints = false; close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    view.addSubview(close)
    NSLayoutConstraint.activate([close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12), close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)])
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(exportFile(_:)))
    view.addGestureRecognizer(longPress)
    resolveFile()
  }

  open func numberOfPreviewItems(in controller: QLPreviewController) -> Int { localURL == nil ? 0 : 1 }
  open func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { localURL! as NSURL }
  @objc open func exportFile(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, let localURL else { return }
    present(UIDocumentPickerViewController(forExporting: [localURL], asCopy: true), animated: true)
  }

  private func resolveFile() {
    if sourceURL.isFileURL { localURL = sourceURL; showQuickLook(); return }
    URLSession.shared.downloadTask(with: sourceURL) { [weak self] url, _, _ in
      guard let self, let url else { return }
      let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + self.sourceURL.lastPathComponent)
      try? FileManager.default.removeItem(at: destination)
      do { try FileManager.default.copyItem(at: url, to: destination) } catch { return }
      Task { @MainActor [weak self] in self?.localURL = destination; self?.showQuickLook() }
    }.resume()
  }
  private func showQuickLook() {
    loading.stopAnimating()
    let quickLook = QLPreviewController(); quickLook.dataSource = self; quickLook.view.translatesAutoresizingMaskIntoConstraints = false
    addChild(quickLook); view.insertSubview(quickLook.view, at: 0)
    NSLayoutConstraint.activate([quickLook.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), quickLook.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), quickLook.view.topAnchor.constraint(equalTo: view.topAnchor), quickLook.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    quickLook.didMove(toParent: self); self.quickLook = quickLook; quickLook.reloadData()
  }
}

/** MapKit location chooser used by PteIMUIKit before a location message is sent. */
@MainActor
open class PteIMUILocationPickerViewController: UIViewController, MKMapViewDelegate, @preconcurrency CLLocationManagerDelegate {
  public var onLocationSelected: ((PteIMLocation) -> Void)?
  public let language: PteIMLanguage
  private let mapView = MKMapView()
  private let locationManager = CLLocationManager()
  private var selectedCoordinate: CLLocationCoordinate2D?
  private var selectedName: String?

  public init(language: PteIMLanguage = .system) { self.language = language; super.init(nibName: nil, bundle: nil) }
  required public init?(coder: NSCoder) { nil }
  open override func viewDidLoad() {
    super.viewDidLoad()
    title = PteIMUILocalization.value("选择位置", "Choose location", language: language)
    view.backgroundColor = .systemBackground
    mapView.translatesAutoresizingMaskIntoConstraints = false; mapView.delegate = self; view.addSubview(mapView)
    NSLayoutConstraint.activate([mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor), mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor), mapView.topAnchor.constraint(equalTo: view.topAnchor), mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: PteIMUILocalization.value("发送", "Send", language: language), style: .done, target: self, action: #selector(send))
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(mapLongPressed(_:))); mapView.addGestureRecognizer(longPress)
    locationManager.delegate = self; locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager.requestWhenInUseAuthorization()
  }
  @objc open func cancel() { dismiss(animated: true) }
  @objc open func send() {
    guard let coordinate = selectedCoordinate else { return }
    let name = selectedName ?? PteIMUILocalization.value("选定位置", "Selected location", language: language)
    onLocationSelected?(PteIMLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name))
    dismiss(animated: true)
  }
  @objc private func mapLongPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    select(mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView))
  }
  open func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
  }
  open func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { if let coordinate = locations.last?.coordinate { select(coordinate, center: true) } }
  open func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
  private func select(_ coordinate: CLLocationCoordinate2D, center: Bool = false) {
    selectedCoordinate = coordinate; mapView.removeAnnotations(mapView.annotations)
    let pin = MKPointAnnotation(); pin.coordinate = coordinate; pin.title = PteIMUILocalization.value("选定位置", "Selected location", language: language); mapView.addAnnotation(pin)
    if center { mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900), animated: true) }
    CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { [weak self] placemarks, _ in
      let place = placemarks?.first
      Task { @MainActor in self?.selectedName = place?.name ?? place?.locality ?? self?.selectedName }
    }
  }
}
