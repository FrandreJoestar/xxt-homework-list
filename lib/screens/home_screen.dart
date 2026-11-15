import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import '../models/homework.dart';
import '../services/calendar_service.dart';
import '../services/chaoxing_client.dart';
import '../services/homework_cache.dart';
import '../services/session_store.dart';
import '../utils/reminder_text.dart';
import '../widgets/card_morph_transition.dart';
import '../widgets/reminder_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLoggedOut});

  final Future<void> Function() onLoggedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ChaoxingClient _client = ChaoxingClient(SessionStore());
  final HomeworkCache _cache = HomeworkCache();
  final Map<HomeworkFilter, ScrollController> _scrollControllers = {};
  final PageController _pageController = PageController();
  final MiuixSnackbarHostState _snackbarHost = MiuixSnackbarHostState();
  final ValueNotifier<bool> _barsVisible = ValueNotifier<bool>(true);
  final GlobalKey _dockTabsKey = GlobalKey();
  bool _dockDragging = false;

  final Set<String> _selectedIds = {};
  final Map<HomeworkFilter, Map<String, GlobalKey>> _cardKeys = {};

  List<Homework> _items = [];
  List<String> _failedCourses = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _importing = false;
  bool _selectionMode = false;
  Duration _reminderLead = const Duration(hours: 2);
  int _selectedTab = 0;
  String? _progress;
  String? _error;
  bool _needLogin = false;

  int _loadEpoch = 0;
  Completer<void>? _refreshCancel;

  bool _dragging = false;
  String? _dragLastCardId;
  Offset? _lastDragPosition;
  late final Ticker _autoScrollTicker;
  double _autoScrollSpeed = 0;
  Duration _lastTickElapsed = Duration.zero;

  final Map<HomeworkFilter, List<Homework>> _sortedCache = {};
  List<Homework> _sortedSource = const [];

  HomeworkFilter get _filter => HomeworkFilter.values[_selectedTab];

  List<Homework> get _currentTabItems => _sortedFor(_filter);

  List<Homework> get _selectedItems =>
      _items.where((h) => _selectedIds.contains(h.id)).toList();

  /// 按分类缓存排序结果，避免长按拖拽自动滚动时每帧重复排序。
  List<Homework> _sortedFor(HomeworkFilter filter) {
    if (!identical(_sortedSource, _items)) {
      _sortedCache.clear();
      _sortedSource = _items;
    }
    return _sortedCache.putIfAbsent(
      filter,
      () => sortedByFilter(_items, filter),
    );
  }

  ScrollController _scrollControllerFor(HomeworkFilter filter) =>
      _scrollControllers.putIfAbsent(filter, () => ScrollController());

  GlobalKey _cardKeyFor(HomeworkFilter filter, String id) =>
      (_cardKeys[filter] ??= {}).putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _autoScrollTicker = createTicker(_onAutoScrollTick);
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
    _autoScrollTicker.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    _snackbarHost.dispose();
    _barsVisible.dispose();
    _client.dispose();
    super.dispose();
  }

  void _selectTab(int index, {bool animate = true}) {
    if (index == _selectedTab) return;
    if (_selectionMode) {
      _selectedIds.clear();
      _selectionMode = false;
      _stopDragSelection();
    }
    setState(() => _selectedTab = index);
    _barsVisible.value = true;
    if (!_pageController.hasClients) return;
    if (animate) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: MiuixMotion.standardDecelerate,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  void _onPageChanged(int index) {
    if (!mounted || index == _selectedTab) return;
    if (_selectionMode) {
      _selectedIds.clear();
      _selectionMode = false;
      _stopDragSelection();
    }
    setState(() => _selectedTab = index);
    _barsVisible.value = true;
  }

  /// 上滑列表时顶栏与 dock 一起滑出屏幕，下滑或回到顶部时再滑入。
  bool _handleScrollNotification(ScrollNotification notification) {
    if (_selectionMode || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 6 && _barsVisible.value) {
        _barsVisible.value = false;
      } else if (delta < -6 && !_barsVisible.value) {
        _barsVisible.value = true;
      }
    } else if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 0) {
      _barsVisible.value = true;
    }
    return false;
  }

  // ------------------------------------------------------------ 分类 dock

  void _handleDockLongPressStart(LongPressStartDetails details) {
    _dockDragging = true;
    HapticFeedback.selectionClick();
    _selectTabAt(details.globalPosition);
  }

  void _handleDockLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_dockDragging) return;
    _selectTabAt(details.globalPosition);
  }

  /// 长按 dock 后左右拖动，手指落在哪个分类上就切到哪个分类。
  void _selectTabAt(Offset globalPosition) {
    final box = _dockTabsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return;
    final dx = globalPosition.dx - box.localToGlobal(Offset.zero).dx;
    final count = HomeworkFilter.values.length;
    final index = (dx / box.size.width * count).floor().clamp(0, count - 1);
    _selectTab(index);
  }

  Future<void> _load() async {
    if (_refreshing) return;
    if (_selectionMode) {
      _selectionMode = false;
      _selectedIds.clear();
      _stopDragSelection();
    }
    final epoch = ++_loadEpoch;
    final cancel = Completer<void>();
    _refreshCancel = cancel;
    setState(() {
      _error = null;
      _needLogin = false;
      _refreshing = true;
      _progress = null;
      if (_items.isEmpty) _loading = true;
    });

    try {
      final fetch = _client.fetchAllHomework(
        onProgress: (done, total) {
          if (!mounted || epoch != _loadEpoch) return;
          setState(() {
            _progress = total == 0 ? '正在读取课程…' : '正在读取课程 $done/$total';
          });
        },
      );
      // 取消时立即结束等待，已发出的网络请求结果会被丢弃。
      final result = await Future.any<HomeworkFetchResult?>([
        fetch,
        cancel.future.then((_) => null),
      ]);
      if (result == null || !mounted || epoch != _loadEpoch) return;
      setState(() {
        _items = result.items;
        _failedCourses = result.failedCourses;
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      _cache.save(result).ignore();
    } on ChaoxingException catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = e.message;
        _needLogin = e.needLogin;
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      if (_items.isNotEmpty) _showMessage(e.message);
    } catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
        _refreshing = false;
        _progress = null;
      });
      if (_items.isNotEmpty) _showMessage('刷新失败：$e');
    } finally {
      if (identical(_refreshCancel, cancel)) _refreshCancel = null;
    }
  }

  /// 取消正在进行的刷新：立即收起刷新状态，后台请求结果会被丢弃。
  void _cancelRefresh() {
    if (!_refreshing) return;
    _loadEpoch++;
    _refreshCancel?.complete();
    _refreshCancel = null;
    setState(() {
      _refreshing = false;
      _progress = null;
    });
    _showMessage('已取消刷新');
  }

  int _countOf(HomeworkFilter filter) =>
      _items.where((h) => h.matches(filter)).length;

  void _showMessage(String message) {
    if (!mounted) return;
    _snackbarHost.showSnackbar(message);
  }

  // ------------------------------------------------------------ 多选

  void _handleTap(Offset globalPosition) {
    final homework = _cardAt(globalPosition);
    if (homework == null) return;
    if (_selectionMode) {
      _toggleSelection(homework);
    } else {
      _openDetail(homework);
    }
  }

  void _handleLongPressStart(Offset globalPosition) {
    final homework = _cardAt(globalPosition);
    if (homework == null) return;
    _startDragSelection(homework);
  }

  Homework? _cardAt(Offset globalPosition) {
    final keys = _cardKeys[_filter];
    if (keys == null) return null;
    for (final homework in _currentTabItems) {
      final context = keys[homework.id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) return homework;
    }
    return null;
  }

  void _toggleSelection(Homework homework) {
    HapticFeedback.selectionClick();
    _barsVisible.value = true;
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.add(homework.id)) {
        _selectedIds.remove(homework.id);
      }
    });
  }

  void _selectAllInTab() {
    HapticFeedback.selectionClick();
    _barsVisible.value = true;
    setState(() {
      _selectionMode = true;
      _selectedIds.addAll(_currentTabItems.map((h) => h.id));
    });
  }

  void _invertSelectionInTab() {
    HapticFeedback.selectionClick();
    _barsVisible.value = true;
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
    _barsVisible.value = true;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 长按进入多选，并在不松手时开启拖动快速多选。
  void _startDragSelection(Homework homework) {
    _stopDragSelection();
    HapticFeedback.mediumImpact();
    _barsVisible.value = true;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(homework.id);
      _dragging = true;
    });
    _dragLastCardId = homework.id;
  }

  void _updateDragSelection(Offset globalPosition) {
    if (!_dragging) return;
    _lastDragPosition = globalPosition;
    _toggleCardAt(globalPosition);
    _updateAutoScroll(globalPosition);
  }

  /// 手指经过某张卡片时切换它的选中状态：
  /// 顺着拖为选中，往回拖就会取消选中（同一张卡片只切换一次）。
  void _toggleCardAt(Offset globalPosition) {
    final homework = _cardAt(globalPosition);
    if (homework == null) {
      _dragLastCardId = null;
      return;
    }
    if (homework.id == _dragLastCardId) return;
    _dragLastCardId = homework.id;
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.remove(homework.id)) {
        _selectedIds.add(homework.id);
      }
    });
  }

  /// 拖到列表顶部/底部附近时自动滚动，便于不松手连续多选。
  void _updateAutoScroll(Offset globalPosition) {
    final controller = _scrollControllerFor(_filter);
    if (!controller.hasClients) return;
    final media = MediaQuery.of(context);
    // 分类栏已移到底部 dock；多选拖拽时列表下方是导入栏。
    final topEdge = media.padding.top + kToolbarHeight + 12;
    final bottomEdge = media.size.height - media.padding.bottom - 110;

    double speed = 0;
    if (globalPosition.dy < topEdge) {
      speed = -_edgeSpeed((topEdge - globalPosition.dy) / 64);
    } else if (globalPosition.dy > bottomEdge) {
      speed = _edgeSpeed((globalPosition.dy - bottomEdge) / 64);
    }
    if (speed == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollSpeed = speed;
    if (_autoScrollTicker.isActive) return;
    _lastTickElapsed = Duration.zero;
    _autoScrollTicker.start();
  }

  /// 越靠近边缘滚得越快，速度限制在 160~640 像素/秒。
  double _edgeSpeed(double ratio) {
    final t = ratio.clamp(0.0, 1.0);
    return 160 + 480 * t;
  }

  /// 每帧按时间增量滚动，避免定时器跳帧造成的卡顿。
  void _onAutoScrollTick(Duration elapsed) {
    if (!mounted || !_dragging) {
      _stopAutoScroll();
      return;
    }
    final controller = _scrollControllerFor(_filter);
    if (!controller.hasClients) {
      _stopAutoScroll();
      return;
    }
    final dt = ((elapsed - _lastTickElapsed).inMicroseconds / 1000000).clamp(
      0.0,
      0.05,
    );
    _lastTickElapsed = elapsed;
    if (dt == 0) return;

    final position = controller.position;
    final next = (position.pixels + _autoScrollSpeed * dt)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next == position.pixels) {
      _autoScrollTicker.stop();
      return;
    }
    controller.jumpTo(next);
    final lastPosition = _lastDragPosition;
    if (lastPosition != null) _toggleCardAt(lastPosition);
  }

  void _stopDragSelection() {
    _dragging = false;
    _dragLastCardId = null;
    _lastDragPosition = null;
    _stopAutoScroll();
  }

  void _stopAutoScroll() {
    _autoScrollSpeed = 0;
    if (_autoScrollTicker.isActive) _autoScrollTicker.stop();
  }

  // ------------------------------------------------------------ 作业详情

  Future<void> _openDetail(Homework homework) async {
    final theme = MiuixTheme.of(context);
    final origin = _cardRectOf(homework);
    final detail = await showGeneralDialog<HomeworkDetail>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭作业详情',
      // 遮罩由 CardMorphTransition 自己绘制，随动画一起淡入淡出。
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _HomeworkDetailDialog(
            homework: homework,
            load: () => _client.fetchHomeworkDetail(homework),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          CardMorphTransition(
            origin: origin,
            animation: animation,
            // 源卡片就是列表里的那张卡片，变形开始时先淡出文字。
            source: _HomeworkCard(
              homework: homework,
              selectionMode: false,
              selected: false,
            ),
            sourceColor: theme.colors.surfaceContainer,
            targetColor: theme.colors.background,
            child: child,
          ),
    );
    if (detail == null || !mounted) return;

    final deadline = detail.deadline ?? homework.deadline;
    if (deadline == null) return;
    await _addSingleToCalendar(homework, deadline);
  }

  /// 卡片在屏幕上的位置，作为详情弹窗展开动画的起点。
  Rect? _cardRectOf(Homework homework) {
    final renderObject = _cardKeys[_filter]?[homework.id]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Future<void> _addSingleToCalendar(
    Homework homework,
    DateTime deadline,
  ) async {
    if (_importing) return;
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
      final result = await CalendarService.addHomeworkEvents([
        homework.copyWithDeadline(deadline),
      ], reminderMinutes: lead.inMinutes);
      final parts = <String>['已添加 ${result.added} 个日程'];
      if (result.skipped > 0) parts.add('${result.skipped} 个已存在');
      if (result.failed > 0) parts.add('${result.failed} 个写入失败');
      _showMessage(
        '${parts.join('，')}；将在截止前 ${formatReminderLead(lead.inMinutes)}提醒',
      );
    } catch (e) {
      _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
    final theme = MiuixTheme.of(context);
    final appBarHeight =
        MediaQuery.paddingOf(context).top +
        MiuixTopAppBarDefaults.smallTopAppBarCenterHeight;
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) _exitSelection();
      },
      child: MiuixScaffold(
        containerColor: theme.colors.background,
        snackbarHost: MiuixSnackbarHost(state: _snackbarHost),
        bottomBar: _selectionMode ? _buildImportBar(theme) : null,
        content: (_) => NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: Stack(
            children: [
              // 顶栏藏起时列表同步向上长高，用真正的顶栏高度做内边距过渡。
              ValueListenableBuilder<bool>(
                valueListenable: _barsVisible,
                builder: (context, visible, child) => AnimatedPadding(
                  padding: EdgeInsets.only(top: visible ? appBarHeight : 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
                child: _buildBody(theme),
              ),
              // 顶栏滑出后状态栏区域仍保留背景色，内容只在其下方滚过。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top,
                child: ColoredBox(color: theme.colors.surface),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _barsVisible,
                  builder: (context, visible, child) => AnimatedSlide(
                    offset: visible ? Offset.zero : const Offset(0, -1.2),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: child,
                  ),
                  child: _buildTopBar(theme),
                ),
              ),
              if (!_selectionMode)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _barsVisible,
                    builder: (context, visible, child) => AnimatedSlide(
                      offset: visible ? Offset.zero : const Offset(0, 1.4),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: child,
                    ),
                    child: _buildCategoryDock(theme),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(MiuixThemeData theme) {
    return MiuixSmallTopAppBar(
      title: _selectionMode ? '已选 ${_selectedIds.length} 项' : '学习通作业本',
      actions: _selectionMode
          ? [
              _buildSelectAction('全选', _selectAllInTab, theme),
              _buildSelectAction('反选', _invertSelectionInTab, theme),
              _buildSelectAction('取消', _exitSelection, theme),
            ]
          : _buildAppBarActions(context),
    );
  }

  /// 底部分类 dock：半透明悬浮面板，盖在列表之上；列表下滑时滑出屏幕，上滑时滑入。
  Widget _buildCategoryDock(MiuixThemeData theme) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: ColoredBox(
                color: theme.colors.surface.withValues(alpha: 0.72),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: _handleDockLongPressStart,
                    onLongPressMoveUpdate: _handleDockLongPressMove,
                    onLongPressEnd: (_) => _dockDragging = false,
                    onLongPressCancel: () => _dockDragging = false,
                    child: KeyedSubtree(
                      key: _dockTabsKey,
                      child: MiuixTabRowWithContour(
                        tabs: [
                          for (final filter in HomeworkFilter.values)
                            '${filter.label} ${_countOf(filter)}',
                        ],
                        selectedTabIndex: _selectedTab,
                        onTabSelected: _selectTab,
                        height: 44,
                        minWidth: 56,
                        maxWidth: 96,
                        itemSpacing: 4,
                        cornerRadius: 20,
                        colors: MiuixTabRowColors(
                          backgroundColor: Colors.transparent,
                          contentColor: theme.colors.onSurfaceVariantSummary,
                          selectedBackgroundColor: theme.colors.primary,
                          selectedContentColor: theme.colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      // 有缓存时刷新中可点击取消；首次加载没有内容可看，只显示进度。
      MiuixIconButton(
        onPressed: _refreshing
            ? (_items.isEmpty ? null : _cancelRefresh)
            : _load,
        child: _refreshing
            ? (_items.isEmpty
                  ? const MiuixCircularProgressIndicator(
                      size: 18,
                      strokeWidth: 2,
                    )
                  : const MiuixIcon(icon: Icons.close_rounded, size: 22))
            : const MiuixIcon(icon: Icons.refresh_rounded, size: 22),
      ),
      MiuixOverlayIconDropdownMenu(
        entry: MiuixDropdownEntry(
          items: [
            MiuixDropdownItem(text: '刷新作业', onClick: _load),
            MiuixDropdownItem(text: '退出登录', onClick: widget.onLoggedOut),
          ],
        ),
        child: const MiuixIcon(icon: Icons.more_vert_rounded, size: 22),
      ),
    ];
  }

  Widget _buildSelectAction(
    String label,
    VoidCallback onPressed,
    MiuixThemeData theme,
  ) {
    return MiuixTextButton(
      label,
      onPressed: onPressed,
      minWidth: 0,
      minHeight: 34,
      insideMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      textStyle: theme.textStyles.footnote1.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildBody(MiuixThemeData theme) {
    if (_loading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiuixCircularProgressIndicator(size: 26, strokeWidth: 2.4),
            const SizedBox(height: 16),
            MiuixText(
              _progress ?? '正在登录学习通…',
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 6),
            MiuixText(
              '首次加载需要逐门课程读取作业，请稍候',
              style: theme.textStyles.footnote2,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _buildError(theme);
    }

    return PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      children: [
        for (final filter in HomeworkFilter.values)
          _buildTabPage(filter, theme),
      ],
    );
  }

  Widget _buildTabPage(HomeworkFilter filter, MiuixThemeData theme) {
    final items = _sortedFor(filter);
    return MiuixPullToRefresh(
      isRefreshing: _refreshing,
      onRefresh: () {
        _load();
      },
      color: theme.colors.primary,
      refreshTexts: const ['下拉刷新', '松开刷新', '正在刷新…', '刷新完成'],
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) => _handleTap(details.globalPosition),
        onLongPressStart: (details) =>
            _handleLongPressStart(details.globalPosition),
        onLongPressMoveUpdate: (details) =>
            _updateDragSelection(details.globalPosition),
        onLongPressEnd: (_) => _stopDragSelection(),
        child: ListView(
          key: PageStorageKey<String>('homework-${filter.name}'),
          controller: _scrollControllerFor(filter),
          physics: const AlwaysScrollableScrollPhysics(),
          // 顶部与顶栏的间距由外层内边距负责；底部留出悬浮 dock 与系统手势区，
          // 这样最后一张卡片也能完整滚到 dock 上方。
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.paddingOf(context).bottom + 78,
          ),
          children: [
            if (_failedCourses.isNotEmpty) _buildFailedBanner(theme),
            if (items.isNotEmpty) _buildUsageHint(theme),
            if (items.isEmpty)
              _buildEmpty(filter, theme)
            else
              for (final homework in items)
                _HomeworkCard(
                  key: _cardKeyFor(filter, homework.id),
                  homework: homework,
                  selectionMode: _selectionMode,
                  selected: _selectedIds.contains(homework.id),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(MiuixThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiuixIcon(
              icon: Icons.cloud_off_rounded,
              size: 44,
              tint: theme.colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 16),
            MiuixText(
              '加载失败',
              style: theme.textStyles.title4.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            MiuixText(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MiuixTextButton('重试', onPressed: _load),
                if (_needLogin) ...[
                  const SizedBox(width: 12),
                  MiuixButton(
                    onPressed: () => widget.onLoggedOut(),
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: const MiuixText('重新登录'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 列表顶部的一句使用提示：点击看详情、长按多选导入日历。
  Widget _buildUsageHint(MiuixThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MiuixSurface(
        cornerRadius: 12,
        color: theme.colors.surfaceContainerHigh,
        contentColor: theme.colors.onSurfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              MiuixIcon(
                icon: Icons.touch_app_outlined,
                size: 14,
                tint: theme.colors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MiuixText(
                  '点击卡片查看作业详情，长按卡片可多选并导入日历',
                  style: theme.textStyles.footnote2.copyWith(height: 1.4),
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedBanner(MiuixThemeData theme) {
    final names = _failedCourses.take(3).join('、');
    final more = _failedCourses.length > 3
        ? ' 等 ${_failedCourses.length} 门'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MiuixSurface(
        cornerRadius: 12,
        color: theme.colors.errorContainer,
        contentColor: theme.colors.onErrorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixIcon(
                icon: Icons.info_outline_rounded,
                size: 16,
                tint: theme.colors.onErrorContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MiuixText(
                  '部分课程的作业未读取到（可能未开放作业功能）：$names$more',
                  style: theme.textStyles.footnote2.copyWith(height: 1.45),
                  color: theme.colors.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(HomeworkFilter filter, MiuixThemeData theme) {
    final (String title, String hint) = switch (filter) {
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
          MiuixSurface(
            cornerRadius: 28,
            color: theme.colors.surfaceContainerHigh,
            contentColor: theme.colors.onSurfaceContainerHigh,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: MiuixIcon(
                  icon: Icons.inbox_rounded,
                  size: 26,
                  tint: Color(0xFF8A8F98),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          MiuixText(
            title,
            style: theme.textStyles.subtitle.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 6),
          MiuixText(
            hint,
            style: theme.textStyles.footnote2,
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  /// 多选时的导入栏。底部安全区由下方分类 dock 统一处理。
  Widget _buildImportBar(MiuixThemeData theme) {
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

    return MiuixSurface(
      color: theme.colors.surface,
      contentColor: theme.colors.onSurface,
      border: Border(top: BorderSide(color: theme.colors.dividerLine)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiuixText(
              hint,
              textAlign: TextAlign.center,
              style: theme.textStyles.footnote2,
              color: theme.colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MiuixButton(
                onPressed: (importable == 0 || _importing)
                    ? null
                    : _importSelected,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_importing)
                      const MiuixCircularProgressIndicator(
                        size: 18,
                        strokeWidth: 2,
                        colors: MiuixProgressIndicatorColors(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          backgroundColor: Colors.white24,
                        ),
                      )
                    else
                      const MiuixIcon(
                        icon: Icons.event_available_rounded,
                        size: 20,
                      ),
                    const SizedBox(width: 8),
                    MiuixText(
                      _importing
                          ? '正在导入…'
                          : importable == 0
                          ? '导入日历'
                          : '导入日历（$importable）',
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final theme = MiuixTheme.of(context);
    final expired = homework.isExpired;
    final submitted = homework.isSubmitted;
    final statusColor = expired
        ? theme.colors.onSurfaceVariantSummary
        : submitted
        ? const Color(0xFF1F7A52)
        : const Color(0xFFB26A00);

    final now = DateTime.now();
    final remaining = _remainingText(now);
    final remainingColor = _remainingColor(now, theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        colors: MiuixCardDefaults.defaultColors(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectionMode) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colors.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colors.primary
                              : theme.colors.outline,
                          width: 1.6,
                        ),
                      ),
                      child: selected
                          ? MiuixIcon(
                              icon: Icons.check_rounded,
                              size: 14,
                              tint: theme.colors.onPrimary,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: MiuixText(
                    homework.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body1.copyWith(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                MiuixSurface(
                  cornerRadius: 20,
                  color: statusColor.withValues(alpha: 0.12),
                  contentColor: statusColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: MiuixText(
                      homework.displayStatus,
                      style: theme.textStyles.footnote2.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                MiuixIcon(
                  icon: Icons.menu_book_outlined,
                  size: 14,
                  tint: theme.colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: MiuixText(
                    homework.course,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote2,
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                MiuixIcon(
                  icon: Icons.schedule_rounded,
                  size: 14,
                  tint: expired
                      ? theme.colors.onSurfaceVariantSummary
                      : theme.colors.onSurface,
                ),
                const SizedBox(width: 5),
                MiuixText(
                  homework.deadline == null
                      ? '截止时间未知'
                      : _formatDeadline(homework.deadline!, now),
                  style: theme.textStyles.footnote2.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  color: expired
                      ? theme.colors.onSurfaceVariantSummary
                      : theme.colors.onSurface,
                ),
                const Spacer(),
                if (remaining != null)
                  MiuixText(
                    remaining,
                    style: theme.textStyles.footnote2.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    color: remainingColor,
                  ),
              ],
            ),
          ],
        ),
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

  Color _remainingColor(DateTime now, MiuixThemeData theme) {
    final deadline = homework.deadline;
    if (deadline == null || homework.isExpired) {
      return theme.colors.onSurfaceVariantSummary;
    }
    final diff = deadline.difference(now);
    if (diff.inHours < 24) return theme.colors.error;
    if (diff.inDays < 3) return const Color(0xFFB26A00);
    return theme.colors.onSurfaceVariantSummary;
  }
}

/// 点击作业卡片后弹出的详情卡片：展示题量 / 满分 / 作答时间 / 得分，
/// 底部提供“添加到日历”与“取消”。关闭时返回 [HomeworkDetail]（取消为 null）。
class _HomeworkDetailDialog extends StatefulWidget {
  const _HomeworkDetailDialog({required this.homework, required this.load});

  final Homework homework;
  final Future<HomeworkDetail> Function() load;

  @override
  State<_HomeworkDetailDialog> createState() => _HomeworkDetailDialogState();
}

class _HomeworkDetailDialogState extends State<_HomeworkDetailDialog> {
  HomeworkDetail? _detail;
  bool _loading = true;
  String? _error;

  DateTime? get _deadline => _detail?.deadline ?? widget.homework.deadline;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final detail = await widget.load();
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ChaoxingException ? e.message : '读取详情失败：$e';
        _loading = false;
      });
    }
  }

  void _confirm() {
    final detail =
        _detail ??
        HomeworkDetail(
          title: widget.homework.title,
          status: widget.homework.status,
          deadline: widget.homework.deadline,
        );
    Navigator.of(context).pop(detail);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final homework = widget.homework;
    final detail = _detail;
    final deadline = _deadline;
    final canAdd = deadline != null && deadline.isAfter(DateTime.now());

    // 只返回面板本身，尺寸与居中由 _CardMorphTransition 负责。
    return Material(
      color: theme.colors.background,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiuixText(
              '作业详情',
              style: theme.textStyles.footnote2.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
              color: theme.colors.primary,
            ),
            const SizedBox(height: 6),
            MiuixText(
              detail?.title ?? homework.title,
              style: theme.textStyles.title4.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                MiuixIcon(
                  icon: Icons.menu_book_outlined,
                  size: 14,
                  tint: theme.colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: MiuixText(
                    homework.course,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote1,
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(theme),
              ],
            ),
            const SizedBox(height: 14),
            const MiuixHorizontalDivider(),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const MiuixCircularProgressIndicator(
                      size: 16,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 10),
                    MiuixText(
                      '正在读取作业详情…',
                      style: theme.textStyles.footnote1,
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ],
                ),
              )
            else ...[
              if (_error != null) _buildError(theme),
              _infoRow(
                theme,
                '题量',
                detail?.questionCount == null
                    ? '—'
                    : '${detail!.questionCount}',
              ),
              _infoRow(
                theme,
                '满分',
                detail?.fullScore == null ? '—' : '${detail!.fullScore}',
              ),
              _infoRow(theme, '作答时间', _timeRange(deadline)),
              _infoRow(
                theme,
                '得分',
                (detail?.score ?? '').isEmpty ? '—' : '${detail!.score} 分',
              ),
            ],
            const SizedBox(height: 6),
            if (!_loading && !canAdd)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MiuixText(
                  deadline == null ? '该作业没有可用的截止时间，无法添加到日历' : '作业已截止，无法添加到日历',
                  style: theme.textStyles.footnote2,
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: MiuixTextButton(
                      '取消',
                      onPressed: () => Navigator.of(context).pop(),
                      minHeight: 48,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    width: double.infinity,
                    child: MiuixButton(
                      onPressed: canAdd ? _confirm : null,
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      minHeight: 48,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          MiuixIcon(
                            icon: Icons.event_available_rounded,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          MiuixText('添加到日历'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(MiuixThemeData theme) {
    final homework = widget.homework;
    final color = homework.isExpired
        ? theme.colors.onSurfaceVariantSummary
        : homework.isSubmitted
        ? const Color(0xFF1F7A52)
        : const Color(0xFFB26A00);
    return MiuixSurface(
      cornerRadius: 20,
      color: color.withValues(alpha: 0.12),
      contentColor: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: MiuixText(
          homework.displayStatus,
          style: theme.textStyles.footnote2.copyWith(
            fontWeight: FontWeight.w600,
          ),
          color: color,
        ),
      ),
    );
  }

  Widget _buildError(MiuixThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MiuixSurface(
        cornerRadius: 10,
        color: theme.colors.errorContainer,
        contentColor: theme.colors.onErrorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixIcon(
                icon: Icons.error_outline_rounded,
                size: 15,
                tint: theme.colors.onErrorContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MiuixText(
                  _error!,
                  style: theme.textStyles.footnote2.copyWith(height: 1.45),
                  color: theme.colors.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(MiuixThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: MiuixText(
              label,
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
          Expanded(
            child: MiuixText(
              value,
              style: theme.textStyles.body2.copyWith(
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeRange(DateTime? deadline) {
    final start = _detail?.startTime;
    if (start == null && deadline == null) return '未知';
    final startText = start == null ? '?' : _formatTime(start);
    final endText = deadline == null ? '?' : _formatTime(deadline);
    final expired = deadline != null && deadline.isBefore(DateTime.now());
    return '$startText 至 $endText${expired ? '（已截止）' : ''}';
  }

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
