import ExpoModulesCore
import PDFKit

class ExpoPdfMarkupView: ExpoView {
  let pdfView = PDFView()
  let onPageChanged = EventDispatcher()
  let onLoadComplete = EventDispatcher()
  let onError = EventDispatcher()

  private var currentSource: String?
  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true

    pdfView.autoScales = true
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical

    addSubview(pdfView)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePageChanged),
      name: .PDFViewPageChanged,
      object: pdfView
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    pdfView.frame = bounds
  }

  // MARK: - Props

  func loadPdf(from source: String) {
    guard source != currentSource else { return }
    currentSource = source

    let fileURL = URL(fileURLWithPath: source)
    guard let document = PDFDocument(url: fileURL) else {
      onError(["message": "Failed to load PDF from: \(source)"])
      return
    }

    pdfView.document = document
    let pageCount = document.pageCount
    onLoadComplete(["pageCount": pageCount])
  }

  func goToPage(_ pageIndex: Int) {
    guard let document = pdfView.document else { return }
    guard pageIndex >= 0, pageIndex < document.pageCount else { return }
    guard let page = document.page(at: pageIndex) else { return }

    // Only navigate if we're not already on this page
    if let currentPage = pdfView.currentPage, document.index(for: currentPage) == pageIndex {
      return
    }

    pdfView.go(to: page)
  }

  // MARK: - Page change notification

  @objc private func handlePageChanged() {
    guard let document = pdfView.document,
          let currentPage = pdfView.currentPage else { return }

    let pageIndex = document.index(for: currentPage)
    let pageCount = document.pageCount
    onPageChanged(["page": pageIndex, "pageCount": pageCount])
  }
}
