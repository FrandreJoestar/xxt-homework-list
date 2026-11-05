import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/homework.dart';
import '../services/calendar_service.dart';
import '../services/chaoxing_client.dart';
import '../services/homework_cache.dart';
import '../services/session_store.dart';
import '../theme.dart';
import '../utils/reminder_text.dart';
import '../widgets/reminder_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLoggedOut});

  final Future<void> Function() onLoggedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ChaoxingClient _client = ChaoxingClient(SessionStore());
  final HomeworkCache _cache = HomeworkCache();
  final ScrollController _scrollController = ScrollController();
  late final TabController _tabController = TabController(
    length: HomeworkFilter.values.length,
    vsync: this,
  );

  final Set<String> _selectedIds = {};
  final Map<String, GlobalKey> _cardKeys = {};

  List<Homework> _items = [];
  List<String> _failedCourses = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _importing = false;
  bool _selectionMode = false;
  Duration _reminderLead = const Duration(hours: 2);
  int _lastTabIndex = 0;
  String? _progress;
  String? _error;
  bool _needLogin = false;

  bool _dragging = false;
  Timer? _autoScrollTimer;
  double _autoScrollDelta = 0;
  Offset? _lastDragPosition;

  HomeworkFilter get _filter => HomeworkFilter.values[_tabController.index];

  List<Homework> get _currentTabItems => sortedByFilter(_items, _filter);

  List<Homework> get _selectedItems =>
      _items.where((h) => _selectedIds.contains(h.id)).toList();

  GlobalKey _cardKeyFor(String id) =>
      _cardKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _lastTabIndex = _tabController.index;
    _tabController.addListener(_onTabChanged);
    _bootstrap();
  }

  /// 优先读取本地缓存：当天已有数据就不再联网，否则后台自动获取一次。
  Future<void> _bootstrap() async {
    final cached = await _cache.read();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _items = cached.items;
        _failedCourses = cached.failedCourses;
        _loading = false;
      });
      if (cached.isFromToday) return;
    }
    await _load();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _client.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    final index = _tabController.index;
    if (index != _lastTabIndex) {
      _lastTabIndex = index;
      if (_selectionMode) {
        _selectedIds.clear();
        _selectionMode = false;
        _stopDragSelection();
      }
    }
    setState(() {});
  }

  Future<void> _load() async {
    if (_refreshing) return;
    if (_selectionMode) {
      _selectionMode = false;
      _selectedIds.clear();
      _stopDragSelection();
    }
    setState(() {
      _error = null;
      _needLogin = false;
      _refreshing = true;
      _progress = null;
      if (_items.isEmpty) _loading = true;
    });

    try {
      final result = await _client.fetchAllHomework(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = total == 0 ? '正在读取课程…' : '正在读取课程 $done/$total';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _failedCourses = result.failedCourses;
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      _cache.save(result).ignore();
    } on ChaoxingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _needLogin = e.needLogin;
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      if (_items.isNotEmpty) _showMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      if (_items.isNotEmpty) _showMessage('刷新失败：$e');
    }
  }

  int _countOf(HomeworkFilter filter) =>
      _items.where((h) => h.matches(filter)).length;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  // ------------------------------------------------------------ 多选

  void _handleTap(Offset globalPosition) {
    if (!_selectionMode) return;
    final homework = _cardAt(globalPosition);
    if (homework != null) _toggleSelection(homework);
  }

  void _handleLongPressStart(Offset globalPosition) {
    final homework = _cardAt(globalPosition);
    if (homework == null) return;
    _startDragSelection(homework);
  }

  Homework? _cardAt(Offset globalPosition) {
    for (final homework in _currentTabItems) {
      final context = _cardKeys[homework.id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) return homework;
    }
    return null;
  }

  void _toggleSelection(Homework homework) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.add(homework.id)) {
        _selectedIds.remove(homework.id);
      }
    });
  }

  void _selectAllInTab() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      _selectedIds.addAll(_currentTabItems.map((h) => h.id));
    });
  }

  void _invertSelectionInTab() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      for (final homework in _currentTabItems) {
        if (!_selectedIds.remove(homework.id)) {
          _selectedIds.add(homework.id);
        }
      }
    });
  }

  void _exitSelection() {
    _stopDragSelection();
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 长按进入多选，并在不松手时开启拖动快速多选。
  void _startDragSelection(Homework homework) {
    _stopDragSelection();
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(homework.id);
      _dragging = true;
    });
  }

  void _updateDragSelection(Offset globalPosition) {
    if (!_dragging) return;
    _lastDragPosition = globalPosition;
    _selectCardsAt(globalPosition);
    _updateAutoScroll(globalPosition);
  }

  void _selectCardsAt(Offset globalPosition) {
    final toAdd = <String>[];
    for (final homework in _currentTabItems) {
      if (_selectedIds.contains(homework.id)) continue;
      final context = _cardKeys[homework.id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) {
        toAdd.add(homework.id);
      }
    }
    if (toAdd.isNotEmpty) {
      setState(() => _selectedIds.addAll(toAdd));
    }
  }

  /// 拖到列表顶部/底部附近时自动滚动，便于不松手连续多选。
  void _updateAutoScroll(Offset globalPosition) {
    if (!_scrollController.hasClients) return;
    final media = MediaQuery.of(context);
    final topEdge = media.padding.top + kToolbarHeight + 46 + 16;
    final bottomEdge = media.size.height - media.padding.bottom - 150;

    double delta = 0;
    if (globalPosition.dy < topEdge) {
      delta = -14;
    } else if (globalPosition.dy > bottomEdge) {
      delta = 14;
    }
    if (delta == 0) {
      _stopAutoScroll();
      return;
    }
    if (_autoScrollTimer != null && delta == _autoScrollDelta) return;

    _stopAutoScroll();
    _autoScrollDelta = delta;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 40), (
      timer,
    ) {
      if (!mounted || !_dragging || !_scrollController.hasClients) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }
      final position = _scrollController.position;
      final next = (position.pixels + _autoScrollDelta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next == position.pixels) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }
      _scrollController.jumpTo(next);
      final lastPosition = _lastDragPosition;
      if (lastPosition != null) _selectCardsAt(lastPosition);
    });
  }

  void _stopDragSelection() {
    _dragging = false;
    _lastDragPosition = null;
    _stopAutoScroll();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDelta = 0;
  }

  // ------------------------------------------------------------ 导入日历

  Future<void> _importSelected() async {
    if (_importing) return;
    final now = DateTime.now();
    final importable = _selectedItems
        .where((h) => h.deadline != null && h.deadline!.isAfter(now))
        .toList();
    if (importable.isEmpty) {
      _showMessage('所选作业没有可导入的未来截止时间');
      return;
    }

    final lead = await showReminderPicker(context, initial: _reminderLead);
    if (lead == null || !mounted) return;
    _reminderLead = lead;

    final granted = await CalendarService.ensurePermission();
    if (!granted) {
      _showMessage('未获得日历权限，请在系统设置中允许后重试');
      return;
    }
    if (!mounted) return;

    setState(() => _importing = true);
    try {
      final result = await CalendarService.addHomeworkEvents(
        importable,
        reminderMinutes: lead.inMinutes,
      );
      final parts = <String>['已添加 ${result.added} 个日程'];
      if (result.skipped > 0) parts.add('${result.skipped} 个已存在');
      if (result.failed > 0) parts.add('${result.failed} 个写入失败');
      _showMessage(
        '${parts.join('，')}；将在截止前 ${formatReminderLead(lead.inMinutes)}提醒',
      );
      if (mounted) _exitSelection();
    } catch (e) {
      _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) _exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectionMode ? '已选 ${_selectedIds.length} 项' : '学习通作业本',
          ),
          actions: _selectionMode
              ? [
                  _buildSelectAction('全选', _selectAllInTab),
                  _buildSelectAction('反选', _invertSelectionInTab),
                  _buildSelectAction('取消', _exitSelection),
                ]
              : [
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _refreshing ? null : _load,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 22),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) {
                      if (value == 'logout') {
                        widget.onLoggedOut();
                      } else if (value == 'refresh') {
                        _load();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'refresh', child: Text('刷新作业')),
                      PopupMenuItem(value: 'logout', child: Text('退出登录')),
                    ],
                  ),
                ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: TabBar(
              controller: _tabController,
              tabs: [
                for (final filter in HomeworkFilter.values)
                  Tab(text: '${filter.label} ${_countOf(filter)}'),
              ],
            ),
          ),
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildImportBar(),
      ),
    );
  }

  Widget _buildSelectAction(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 16),
            Text(
              _progress ?? '正在登录学习通…',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '首次加载需要逐门课程读取作业，请稍候',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _buildError();
    }

    final items = sortedByFilter(_items, _filter);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) => _handleTap(details.globalPosition),
            onLongPressStart: (details) =>
                _handleLongPressStart(details.globalPosition),
            onLongPressMoveUpdate: (details) =>
                _updateDragSelection(details.globalPosition),
            onLongPressEnd: (_) => _stopDragSelection(),
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_failedCourses.isNotEmpty) _buildFailedBanner(),
                if (items.isEmpty)
                  _buildEmpty()
                else
                  for (final homework in items)
                    _HomeworkCard(
                      key: _cardKeyFor(homework.id),
                      homework: homework,
                      selectionMode: _selectionMode,
                      selected: _selectedIds.contains(homework.id),
                    ),
              ],
            ),
          ),
        ),
        if (_refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            const Text(
              '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: _load, child: const Text('重试')),
                if (_needLogin) ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => widget.onLoggedOut(),
                    child: const Text('重新登录'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedBanner() {
    final names = _failedCourses.take(3).join('、');
    final more = _failedCourses.length > 3
        ? ' 等 ${_failedCourses.length} 门'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.pending,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '部分课程的作业未读取到（可能未开放作业功能）：$names$more',
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.pending,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final (String title, String hint) = switch (_filter) {
      HomeworkFilter.all => ('还没有作业', '下拉可刷新'),
      HomeworkFilter.pending => ('没有待交作业', '当前作业都已完成或已截止'),
      HomeworkFilter.submitted => ('暂无已交作业', '已截止的作业不会出现在这里'),
      HomeworkFilter.expired => ('暂无已截止作业', '截止时间一过就会归档到这里'),
    };
    return SizedBox(
      height: 340,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(
              Icons.inbox_rounded,
              size: 26,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget? _buildImportBar() {
    if (!_selectionMode) return null;

    final now = DateTime.now();
    final selected = _selectedItems;
    final importable = selected
        .where((h) => h.deadline != null && h.deadline!.isAfter(now))
        .length;

    final hint = selected.isEmpty
        ? '点击作业卡片进行选择'
        : importable == selected.length
        ? '已选 ${selected.length} 项 · 导入时可设置提前提醒时间'
        : '已选 ${selected.length} 项，其中 $importable 项可导入（其余无可用的未来截止时间）';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (importable == 0 || _importing)
                    ? null
                    : _importSelected,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.event_available_rounded, size: 20),
                label: Text(
                  _importing
                      ? '正在导入…'
                      : importable == 0
                      ? '导入日历'
                      : '导入日历（$importable）',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeworkCard extends StatelessWidget {
  const _HomeworkCard({
    super.key,
    required this.homework,
    required this.selectionMode,
    required this.selected,
  });

  final Homework homework;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final expired = homework.isExpired;
    final submitted = homework.isSubmitted;
    final statusColor = expired
        ? AppColors.muted
        : submitted
        ? AppColors.success
        : AppColors.pending;

    final now = DateTime.now();
    final remaining = _remainingText(now);
    final remainingColor = _remainingColor(now);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.045)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.line,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.accent : AppColors.line,
                        width: 1.6,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  homework.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  homework.displayStatus,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 14,
                color: AppColors.muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  homework.course,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: expired ? AppColors.muted : AppColors.ink,
              ),
              const SizedBox(width: 5),
              Text(
                homework.deadline == null
                    ? '截止时间未知'
                    : _formatDeadline(homework.deadline!, now),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: expired ? AppColors.muted : AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (remaining != null)
                Text(
                  remaining,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: remainingColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDeadline(DateTime deadline, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final yearPrefix = deadline.year == now.year ? '' : '${deadline.year}-';
    return '$yearPrefix${two(deadline.month)}-${two(deadline.day)} '
        '${two(deadline.hour)}:${two(deadline.minute)}';
  }

  String? _remainingText(DateTime now) {
    final deadline = homework.deadline;
    if (deadline == null) return null;
    if (homework.isExpired) return '已截止';
    final diff = deadline.difference(now);
    if (diff.inDays >= 1) return '剩 ${diff.inDays} 天';
    if (diff.inHours >= 1) return '剩 ${diff.inHours} 小时';
    if (diff.inMinutes >= 1) return '剩 ${diff.inMinutes} 分钟';
    return '不足 1 分钟';
  }

  Color _remainingColor(DateTime now) {
    final deadline = homework.deadline;
    if (deadline == null || homework.isExpired) return AppColors.muted;
    final diff = deadline.difference(now);
    if (diff.inHours < 24) return AppColors.danger;
    if (diff.inDays < 3) return AppColors.pending;
    return AppColors.muted;
  }
}
