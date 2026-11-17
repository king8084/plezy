import Flutter
import UIKit

#if os(tvOS)
  /// Apple's own search keyboard for Plezy's Search screen: the single row of
  /// letters at the top of the screen, with "hold the mic to dictate" from the
  /// Siri Remote. Presented over the Flutter view, so Plezy's results stay
  /// visible underneath and update as the text changes.
  ///
  /// Channel `plezy/native_search`:
  /// - `open {text, placeholder}` -> Bool (false when it cannot be shown)
  /// - `close`
  /// - callbacks: `changed(text)`, `ended {event: submit|down|dismissed, text}`
  final class NativeSearchPlugin: NSObject, FlutterPlugin, UISearchResultsUpdating, UISearchBarDelegate {
    private let channel: FlutterMethodChannel
    private var container: NativeSearchContainerViewController?
    private var ended = false

    static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(name: "plezy/native_search", binaryMessenger: registrar.messenger())
      let instance = NativeSearchPlugin(channel: channel)
      registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(channel: FlutterMethodChannel) {
      self.channel = channel
      super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "open":
        let arguments = call.arguments as? [String: Any]
        open(
          text: arguments?["text"] as? String ?? "",
          placeholder: arguments?["placeholder"] as? String ?? "",
          result: result
        )
      case "close":
        end(event: "dismissed", animated: false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private func open(text: String, placeholder: String, result: @escaping FlutterResult) {
      guard container == nil, let presenter = Self.topViewController() else {
        result(false)
        return
      }
      let results = NativeSearchResultsViewController()
      let search = UISearchController(searchResultsController: results)
      search.searchResultsUpdater = self
      search.obscuresBackgroundDuringPresentation = false
      search.searchBar.delegate = self
      search.searchBar.placeholder = placeholder
      search.searchBar.text = text

      let containerController = NativeSearchContainerViewController(searchController: search)
      containerController.modalPresentationStyle = .overFullScreen
      containerController.view.backgroundColor = .clear
      results.onFocused = { [weak self] in
        self?.end(event: "down", animated: true)
      }
      containerController.onDisappear = { [weak self] in
        self?.end(event: "dismissed", animated: false)
      }

      ended = false
      container = containerController
      presenter.present(containerController, animated: true) {
        result(true)
      }
    }

    /// Reports how the keyboard was left and dismisses it once.
    private func end(event: String, animated: Bool) {
      guard let containerController = container, !ended else { return }
      ended = true
      container = nil
      let text = containerController.searchController.searchBar.text ?? ""
      channel.invokeMethod("ended", arguments: ["event": event, "text": text])
      if containerController.presentingViewController != nil && !containerController.isBeingDismissed {
        containerController.dismiss(animated: animated)
      }
    }

    func updateSearchResults(for searchController: UISearchController) {
      guard !ended else { return }
      channel.invokeMethod("changed", arguments: searchController.searchBar.text ?? "")
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
      end(event: "submit", animated: true)
    }

    private static func topViewController() -> UIViewController? {
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
      while let presented = top?.presentedViewController {
        top = presented
      }
      return top
    }
  }

  /// Reports a dismissal the user made with the Menu button.
  final class NativeSearchContainerViewController: UISearchContainerViewController {
    var onDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      onDisappear?()
    }
  }

  /// A transparent results area holding one thin focusable strip: moving down
  /// from the keyboard focuses it, which hands focus back to Plezy's results.
  final class NativeSearchResultsViewController: UIViewController {
    var onFocused: (() -> Void)?
    private let focusTarget = NativeSearchFocusTarget()

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      focusTarget.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(focusTarget)
      NSLayoutConstraint.activate([
        focusTarget.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        focusTarget.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        focusTarget.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
        focusTarget.heightAnchor.constraint(equalToConstant: 10),
      ])
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [focusTarget] }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
      super.didUpdateFocus(in: context, with: coordinator)
      if context.nextFocusedView === focusTarget {
        onFocused?()
      }
    }
  }

  final class NativeSearchFocusTarget: UIView {
    override var canBecomeFocused: Bool { true }
  }
#endif
