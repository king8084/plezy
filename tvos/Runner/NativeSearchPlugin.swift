import Flutter
import UIKit

#if os(tvOS)
  /// Apple's own search keyboard docked into Plezy's Search page, the way
  /// Neptune and Apple's apps show it: the big query line and the one-row
  /// keyboard at the top of the page, results underneath, hold the Siri
  /// Remote's mic to dictate. The keyboard is a child view of the Flutter
  /// view controller placed in a rectangle the Search page reserves; it is not
  /// presented over the page.
  ///
  /// Focus is handed back and forth: Down from the keyboard focuses a thin
  /// strip below it, which tells Flutter to focus its first result and makes
  /// the keyboard unfocusable; Flutter's `focus` call makes it focusable again
  /// and moves the focus engine onto it.
  ///
  /// Channel `plezy/native_search`:
  /// - `dock {x, y, width, height, text, placeholder}` -> Bool
  /// - `focus`, `blur`, `undock`, `setText {text}`, `setVisible {visible}`
  /// - callbacks: `changed(text)`, `down`, `submit(text)`
  final class NativeSearchPlugin: NSObject, FlutterPlugin, UISearchResultsUpdating, UISearchBarDelegate {
    private let channel: FlutterMethodChannel
    private var container: UISearchContainerViewController?
    private var results: NativeSearchResultsViewController?
    private var suppressChanges = false

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
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "dock":
        result(dock(arguments))
      case "focus":
        setFocused(true)
        result(nil)
      case "blur":
        setFocused(false)
        result(nil)
      case "setVisible":
        container?.view.isHidden = !((arguments["visible"] as? Bool) ?? true)
        result(nil)
      case "setText":
        if let search = container?.searchController {
          suppressChanges = true
          search.searchBar.text = arguments["text"] as? String ?? ""
          suppressChanges = false
        }
        result(nil)
      case "undock":
        undock()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private static func number(_ value: Any?) -> CGFloat {
      if let number = value as? NSNumber { return CGFloat(truncating: number) }
      return 0
    }

    private func dock(_ arguments: [String: Any]) -> Bool {
      guard let root = Self.rootViewController() else { return false }
      let frame = CGRect(
        x: Self.number(arguments["x"]),
        y: Self.number(arguments["y"]),
        width: Self.number(arguments["width"]),
        height: Self.number(arguments["height"])
      )
      if let existing = container {
        existing.view.frame = frame
        return true
      }
      let resultsController = NativeSearchResultsViewController()
      resultsController.onFocused = { [weak self] in
        guard let self = self else { return }
        self.setFocused(false)
        self.channel.invokeMethod("down", arguments: nil)
      }
      let search = UISearchController(searchResultsController: resultsController)
      search.searchResultsUpdater = self
      search.obscuresBackgroundDuringPresentation = false
      search.searchBar.delegate = self
      search.searchBar.placeholder = arguments["placeholder"] as? String ?? ""
      search.searchBar.text = arguments["text"] as? String ?? ""

      let containerController = UISearchContainerViewController(searchController: search)
      containerController.view.backgroundColor = .clear
      containerController.view.frame = frame
      // Unfocusable until Plezy hands it the remote (`focus`), so docking
      // never steals focus from wherever the user is on the page.
      containerController.view.isUserInteractionEnabled = false
      root.addChild(containerController)
      root.view.addSubview(containerController.view)
      containerController.didMove(toParent: root)
      container = containerController
      results = resultsController
      return true
    }

    private func undock() {
      guard let containerController = container else { return }
      setFocused(false)
      containerController.willMove(toParent: nil)
      containerController.view.removeFromSuperview()
      containerController.removeFromParent()
      container = nil
      results = nil
    }

    /// Focusable keyboard (typing) or not (Flutter's results have focus; the
    /// keyboard stays visible but takes no presses).
    private func setFocused(_ focused: Bool) {
      guard let containerController = container, let root = Self.rootViewController() else { return }
      containerController.view.isUserInteractionEnabled = focused
      if let plezyRoot = root as? PlezyFlutterViewController {
        plezyRoot.nativeSearchFocusEnvironment = focused ? containerController : nil
      }
      root.setNeedsFocusUpdate()
      root.updateFocusIfNeeded()
    }

    func updateSearchResults(for searchController: UISearchController) {
      guard !suppressChanges else { return }
      channel.invokeMethod("changed", arguments: searchController.searchBar.text ?? "")
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
      channel.invokeMethod("submit", arguments: searchBar.text ?? "")
    }

    private static func rootViewController() -> UIViewController? {
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }
  }

  /// The results area below the keyboard: transparent, with one thin
  /// focusable strip at its top. Moving down from the keyboard focuses it,
  /// which hands focus to Plezy's own results.
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
        focusTarget.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
        focusTarget.heightAnchor.constraint(equalToConstant: 8),
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
