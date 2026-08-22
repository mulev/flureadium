import UIKit

extension UIView {
  /// Adds `child` and constrains it to this view's four edges.
  ///
  /// Every reader view hosts its navigator this way: margins and safe area are
  /// handled on the Flutter side, so the navigator fills the container exactly.
  func addPinnedSubview(_ child: UIView) {
    addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: leadingAnchor),
      child.trailingAnchor.constraint(equalTo: trailingAnchor),
      child.topAnchor.constraint(equalTo: topAnchor),
      child.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}
