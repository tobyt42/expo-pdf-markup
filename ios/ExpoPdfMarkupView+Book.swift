import PDFKit
import UIKit

/// Which way a book mode turn goes. `next` is always the page after, whatever the layout direction.
enum BookTurnDirection {
  case previous
  case next

  var step: Int {
    self == .next ? 1 : -1
  }
}

/// What asked for a turn. The turn policy treats touch input and hardware keys differently.
enum BookTurnInput {
  case swipe
  case edgeTap
  /// Hardware keys (#98): turn in book mode whatever the zoom or markup mode.
  case key
}

extension ExpoPdfMarkupView {
  // MARK: - Book mode presentation

  var isBookMode: Bool {
    displayMode == "book"
  }

  /// Switches PDFKit between the continuous scroll and the one-page-at-a-time book layout,
  /// keeping the page the reader is on.
  func applyDisplayMode() {
    let keptPage = pdfView.currentPage

    if isBookMode {
      pdfView.displayMode = .singlePage
      pdfView.displayDirection = .horizontal
      pdfView.pageBreakMargins = .zero
      installBookGestures()
    } else {
      removeBookGestures()
      if isFirstResponder {
        resignFirstResponder()
      }
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical
      pdfView.pageBreakMargins = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
    }
    pdfView.autoScales = true

    if let keptPage {
      pdfView.go(to: keptPage)
    }
    claimBookKeyFocus()
  }

  // MARK: - Hardware keys

  /// The turn a hardware key asks for: Right, Down and Page Down go forward; Left, Up and
  /// Page Up go back. Space isn't mapped.
  func bookTurnDirection(forKey input: String) -> BookTurnDirection? {
    switch input {
    case UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputPageDown:
      .next
    case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow, UIKeyCommand.inputPageUp:
      .previous
    default:
      nil
    }
  }

  /// Key commands for keyboards and page-turner pedals, offered to UIKit only in book mode.
  /// Unmodified keys only, and ahead of the system's own arrow-key scrolling.
  var bookKeyCommands: [UIKeyCommand] {
    [
      UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputPageDown,
      UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow, UIKeyCommand.inputPageUp,
    ].map { input in
      let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(handleBookKeyCommand(_:)))
      command.wantsPriorityOverSystemBehavior = true
      return command
    }
  }

  @objc func handleBookKeyCommand(_ command: UIKeyCommand) {
    guard let input = command.input, let direction = bookTurnDirection(forKey: input) else { return }
    // Keys typed into a text input (including the host's text annotation input) are its own.
    guard !isTextInputActive else { return }
    turnBookPage(direction, from: .key)
  }

  /// Whether a text input outside this view is first responder, so keys belong to it.
  /// PDFKit's own views inside this one don't count.
  var isTextInputActive: Bool {
    guard let responder = UIResponder.currentFirstResponder, responder is UITextInput else { return false }
    return !((responder as? UIView)?.isDescendant(of: self) ?? false)
  }

  /// Becomes first responder in book mode while on screen, so a pedal or keyboard turns the page
  /// without the host app doing anything. Never takes focus from a text input, and leaves it
  /// alone when it's already with this view or PDFKit's views inside it.
  func claimBookKeyFocus() {
    guard isBookMode, window != nil, !isTextInputActive else { return }
    if let current = UIResponder.currentFirstResponder as? UIView, current.isDescendant(of: self) {
      return
    }
    becomeFirstResponder()
  }

  @objc func handleTextEditingEnded() {
    // Wait for the responder change to settle before taking the keys back.
    DispatchQueue.main.async { [weak self] in
      self?.claimBookKeyFocus()
    }
  }

  // MARK: - Turn path

  /// The single entry point for every book mode turn: swipes, edge taps and hardware keys.
  /// Applies the turn policy, then either slides to the neighbouring page (one `onPageChanged`)
  /// or bounces at the first and last page.
  ///
  /// `dragOffset` is how far a swipe has already dragged the page, so the slide carries on from there.
  @discardableResult
  func turnBookPage(_ direction: BookTurnDirection, from input: BookTurnInput, dragOffset: CGFloat = 0) -> Bool {
    guard allowsBookTurn(from: input) else {
      springBookPageBack()
      return false
    }
    guard let target = bookNeighbour(direction) else {
      if dragOffset == 0 {
        animateBookBounce(direction)
      } else {
        springBookPageBack()
      }
      return false
    }
    showBookPage(target, direction: direction, dragOffset: dragOffset)
    return true
  }

  /// Spec turn policy: touch input turns only with no markup tool active and the page at fit.
  /// Keys turn in book mode regardless.
  func allowsBookTurn(from input: BookTurnInput) -> Bool {
    guard isBookMode else { return false }
    switch input {
    case .key:
      return true
    case .swipe, .edgeTap:
      return currentMode == "none" && !isZoomedBeyondFit
    }
  }

  var isZoomedBeyondFit: Bool {
    pdfView.scaleFactor > pdfView.scaleFactorForSizeToFit * 1.01
  }

  func bookNeighbour(_ direction: BookTurnDirection) -> PDFPage? {
    guard let document = pdfView.document, let current = pdfView.currentPage else { return nil }
    let index = document.index(for: current) + direction.step
    guard index >= 0, index < document.pageCount else { return nil }
    return document.page(at: index)
  }

  private func showBookPage(_ page: PDFPage, direction: BookTurnDirection, dragOffset: CGFloat = 0) {
    let width = max(pdfView.bounds.width, 1)
    let outgoing = pdfView.snapshotView(afterScreenUpdates: false)
    finishBookAnimation()

    pdfView.transform = .identity
    pdfView.go(to: page)
    pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    pdfView.autoScales = true

    guard window != nil else { return }

    if let outgoing {
      outgoing.frame = pdfView.frame.offsetBy(dx: dragOffset, dy: 0)
      addSubview(outgoing)
      bookTurnSnapshot = outgoing
    }
    // Next slides in from the right, previous from the left.
    let incomingStart = direction == .next ? width + dragOffset : -width + dragOffset
    pdfView.transform = CGAffineTransform(translationX: incomingStart, y: 0)
    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      self.pdfView.transform = .identity
      outgoing?.transform = CGAffineTransform(translationX: direction == .next ? -width : width, y: 0)
    } completion: { _ in
      outgoing?.removeFromSuperview()
      if self.bookTurnSnapshot === outgoing {
        self.bookTurnSnapshot = nil
      }
    }
  }

  private func animateBookBounce(_ direction: BookTurnDirection) {
    guard window != nil else { return }
    let nudge: CGFloat = direction == .next ? -32 : 32
    UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      self.pdfView.transform = CGAffineTransform(translationX: nudge, y: 0)
    } completion: { _ in
      self.springBookPageBack()
    }
  }

  func springBookPageBack() {
    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      usingSpringWithDamping: 0.7,
      initialSpringVelocity: 0,
      options: [.allowUserInteraction]
    ) {
      self.pdfView.transform = .identity
    }
  }

  private func finishBookAnimation() {
    pdfView.layer.removeAllAnimations()
    bookTurnSnapshot?.removeFromSuperview()
    bookTurnSnapshot = nil
  }

  // MARK: - Edge taps

  /// Width of each edge tap zone: the outer quarter of the view, at least 44 pt.
  var bookEdgeZoneWidth: CGFloat {
    min(max(bounds.width * 0.25, 44), bounds.width / 2)
  }

  /// Turns the page for a tap at `location` (in this view's coordinates) if it lands in an edge zone.
  func handleBookTap(at location: CGPoint) {
    let zone = bookEdgeZoneWidth
    if location.x <= zone {
      turnBookPage(.previous, from: .edgeTap)
    } else if location.x >= bounds.width - zone {
      turnBookPage(.next, from: .edgeTap)
    }
  }

  @objc func handleBookTapGesture(_ gesture: UITapGestureRecognizer) {
    guard gesture.state == .ended else { return }
    claimBookKeyFocus()
    handleBookTap(at: gesture.location(in: self))
  }

  // MARK: - Swipes

  @objc func handleBookPanGesture(_ gesture: UIPanGestureRecognizer) {
    let translationX = gesture.translation(in: self).x
    switch gesture.state {
    case .changed:
      // Follow the finger, with resistance where there is no page to turn to.
      let direction: BookTurnDirection = translationX < 0 ? .next : .previous
      let offset = bookNeighbour(direction) == nil ? translationX * 0.3 : translationX
      pdfView.transform = CGAffineTransform(translationX: offset, y: 0)
    case .ended:
      endBookSwipe(translationX: translationX, velocityX: gesture.velocity(in: self).x)
    case .cancelled, .failed:
      springBookPageBack()
    default:
      break
    }
  }

  /// Ends a horizontal swipe: turns when it went far enough (a quarter of the width) or was
  /// flicked, otherwise springs back. Swipe left always means next.
  func endBookSwipe(translationX: CGFloat, velocityX: CGFloat) {
    let reference = translationX != 0 ? translationX : velocityX
    guard reference != 0 else {
      springBookPageBack()
      return
    }
    let direction: BookTurnDirection = reference < 0 ? .next : .previous
    let farEnough = abs(translationX) > bounds.width * 0.25
    let flicked = abs(velocityX) > 500 && (velocityX < 0) == (reference < 0)
    guard farEnough || flicked else {
      springBookPageBack()
      return
    }
    turnBookPage(direction, from: .swipe, dragOffset: pdfView.transform.tx)
  }

  /// Whether a book mode gesture may start. A pan starts only when it's mostly horizontal and the
  /// turn policy allows a swipe, so while zoomed in the scroll view pans instead.
  func shouldBeginBookGesture(_ gesture: UIGestureRecognizer) -> Bool {
    if gesture === bookPanGesture, let pan = gesture as? UIPanGestureRecognizer {
      let velocity = pan.velocity(in: self)
      return allowsBookTurn(from: .swipe) && abs(velocity.x) > abs(velocity.y)
    }
    if gesture === bookTapGesture {
      return allowsBookTurn(from: .edgeTap)
    }
    return true
  }

  // MARK: - Gestures

  private func installBookGestures() {
    guard bookTapGesture == nil else { return }
    let delegate = BookGestureDelegate(view: self)
    bookGestureDelegate = delegate

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBookTapGesture(_:)))
    tap.delegate = delegate
    pdfView.addGestureRecognizer(tap)
    bookTapGesture = tap

    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBookPanGesture(_:)))
    pan.maximumNumberOfTouches = 1
    pan.delegate = delegate
    pdfView.addGestureRecognizer(pan)
    bookPanGesture = pan
  }

  private func removeBookGestures() {
    finishBookAnimation()
    pdfView.transform = .identity
    if let tap = bookTapGesture {
      pdfView.removeGestureRecognizer(tap)
      bookTapGesture = nil
    }
    if let pan = bookPanGesture {
      pdfView.removeGestureRecognizer(pan)
      bookPanGesture = nil
    }
    bookGestureDelegate = nil
  }
}

/// Gates the book mode tap and pan with the turn policy, and lets them run alongside PDFKit's
/// own gestures. Kept apart from the view's delegate so the markup gestures are unaffected.
final class BookGestureDelegate: NSObject, UIGestureRecognizerDelegate {
  private weak var view: ExpoPdfMarkupView?

  init(view: ExpoPdfMarkupView) {
    self.view = view
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    view?.shouldBeginBookGesture(gestureRecognizer) ?? false
  }

  func gestureRecognizer(
    _: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

extension UIResponder {
  @MainActor private weak static var probedFirstResponder: UIResponder?

  /// The app's current first responder, if any, found by sending an action down the responder chain.
  @MainActor static var currentFirstResponder: UIResponder? {
    probedFirstResponder = nil
    UIApplication.shared.sendAction(#selector(probeFirstResponder), to: nil, from: nil, for: nil)
    return probedFirstResponder
  }

  @objc private func probeFirstResponder() {
    UIResponder.probedFirstResponder = self
  }
}
