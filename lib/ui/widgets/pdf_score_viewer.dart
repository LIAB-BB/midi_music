import 'package:flutter/cupertino.dart';

/// 展示已随应用打包的 PDF 页面图像。
///
/// 页面由经过审核的原始 PDF 预渲染而来，避免把 MIDI 自动转谱的结果
/// 当作可靠的五线谱。阅读时支持翻页与双指缩放。
class PdfScoreViewer extends StatefulWidget {
  final String pageAssetPrefix;
  final int pageCount;
  final String label;

  const PdfScoreViewer({
    super.key,
    required this.pageAssetPrefix,
    required this.pageCount,
    required this.label,
  });

  @override
  State<PdfScoreViewer> createState() => _PdfScoreViewerState();
}

class _PdfScoreViewerState extends State<PdfScoreViewer> {
  late final PageController _pageController;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page < 0 || page >= widget.pageCount) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  String _assetFor(int page) {
    return '${widget.pageAssetPrefix}-${(page + 1).toString().padLeft(2, '0')}.png';
  }

  @override
  Widget build(BuildContext context) {
    final hasPrevious = _currentPage > 0;
    final hasNext = _currentPage < widget.pageCount - 1;
    return Container(
      key: const Key('pdf-score-viewer'),
      decoration: BoxDecoration(
        color: const Color(0xFF24201C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF806F5A)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.doc_richtext,
                  size: 15,
                  color: Color(0xFFF4DFAE),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
                Text(
                  '${_currentPage + 1} / ${widget.pageCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFCEBFAE),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pageCount,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, page) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(32),
                  child: Center(
                    child: Image.asset(
                      _assetFor(page),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: '${widget.label}，第 ${page + 1} 页',
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 8),
            child: Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 0),
                  onPressed: hasPrevious
                      ? () => _goToPage(_currentPage - 1)
                      : null,
                  child: const Icon(CupertinoIcons.chevron_left, size: 17),
                ),
                const Expanded(
                  child: Text(
                    '左右滑动翻页 · 双指缩放',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Color(0xFFCABCA9)),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 0),
                  onPressed: hasNext ? () => _goToPage(_currentPage + 1) : null,
                  child: const Icon(CupertinoIcons.chevron_right, size: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
