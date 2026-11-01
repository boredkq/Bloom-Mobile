/// Тосты Bloom — родня десктопного `GlobalToast` (`#toast` в `search-misc.css`):
/// значок вида, текст, кнопка «Отменить» и видимый обратный отсчёт.
///
/// Вид телефонный, не портированный: стеклянная КАПСУЛА (та же поверхность,
/// что у шторок и баров — [GlassBox]), а отсчёт идёт КОЛЬЦОМ вокруг значка, а
/// не полосой по низу. Полоса осталась ровно за прогрессом долгих работ
/// ([ToastHandle.update]) — там она показывает долю, а не время.
///
/// Почему поверх `ScaffoldMessenger`, а не свой оверлей: очередь (тосты не
/// налезают друг на друга, а ждут очереди), смахивание, снятие вместе с
/// экраном и позиционирование НАД нижними барами — всё это у него уже есть.
/// Мы забираем у него только внешний вид: сам `SnackBar` делается прозрачным
/// и без тени, а рисует всё [BloomToastCard].
///
/// Чтобы тост оказался над миниплеером, бары шелла лежат в
/// `Scaffold.bottomNavigationBar` (см. `app/shell.dart`) — плавающий снекбар
/// встаёт ровно над ними.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';

/// Вид тоста: от него зависят значок и цвет полосы (те же четыре, что на ПК).
enum ToastKind { info, success, warn, error }

/// Действие в тосте — «Отменить» десктопного `ToastAction`.
class ToastAction {
  const ToastAction({required this.fn, this.label, this.onExpire});

  /// Что делать по нажатию (обычно — вернуть удалённое).
  final VoidCallback fn;

  /// Текст кнопки; по умолчанию «Отменить».
  final String? label;

  /// Тост погас сам, без нажатия. Сюда вешается то, что нельзя было делать
  /// сразу, потому что отмена ещё возможна (например, удаление файла обложки).
  final VoidCallback? onExpire;
}

/// Сколько тост висит: обычный и с кнопкой — как на ПК (2с и 5с).
const Duration _plain = Duration(milliseconds: 2000);
const Duration _withAction = Duration(milliseconds: 5000);

/// Пока тост въезжает, `ScaffoldMessenger` ещё не завёл свой таймер — на
/// столько же откладывается и полоса, иначе она уходит вперёд отсчёта.
const Duration _enter = Duration(milliseconds: 250);

/// Долгий тост живёт до `close()`, но `SnackBar` требует конечный срок —
/// берём заведомо больший, чем любая загрузка.
const Duration _openEnded = Duration(minutes: 30);

/// Сколько итог висит после `finish()`.
const Duration _finished = Duration(milliseconds: 2400);

/// Мессенджер приложения (ставится в `MaterialApp.scaffoldMessengerKey`).
///
/// Нужен тем, у кого нет `BuildContext`: авто-обновление плейлистов ходит по
/// расписанию из таймера, а сказать о новых треках всё равно надо.
final GlobalKey<ScaffoldMessengerState> bloomMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension BloomToasts on ScaffoldMessengerState {
  /// Обычный тост: текст, значок вида и полоса отсчёта.
  ///
  /// С [action] живёт дольше (5с) и показывает кнопку; если её не нажать,
  /// сработает `action.onExpire`.
  void toast(
    String text, {
    ToastKind kind = ToastKind.info,
    ToastAction? action,
  }) {
    final duration = action == null ? _plain : _withAction;
    var used = false;
    late ScaffoldFeatureController<SnackBar, SnackBarClosedReason> entry;

    entry = _show(
      this,
      duration: duration,
      child: BloomToastCard(
        text: text,
        kind: kind,
        barDuration: duration,
        // Подпись по умолчанию ставит сама карточка: здесь `BuildContext`
        // взять негде — тост зовут и из таймеров.
        actionLabel: action?.label,
        hasAction: action != null,
        onAction: action == null
            ? null
            : () {
                used = true;
                entry.close();
                action.fn();
              },
      ),
    );

    if (action?.onExpire != null) {
      // Смахнули — это тоже «не нажал отмену»: решение остаётся в силе.
      unawaited(
        entry.closed.then((_) {
          if (!used) action!.onExpire!.call();
        }),
      );
    }
  }

  /// Тост «идёт работа»: значок заменён вертушкой, полосы-таймера нет, и живёт
  /// он до [ToastHandle.finish]. Заменяет пару «Скачиваю…» → «Скачано»: вместо
  /// двух тостов подряд один, который меняется на месте.
  ///
  /// [content] позволяет подменить всю карточку — так тост пакетной загрузки
  /// подписывается на стор и сам обновляет счётчик.
  ToastHandle busyToast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Widget Function(ValueListenable<ToastView>)? content,
  }) {
    final view = ValueNotifier(
      ToastView(text: text, actionLabel: actionLabel, onAction: onAction),
    );
    final entry = _show(
      this,
      duration: _openEnded,
      child: content == null ? _LiveToast(view: view) : content(view),
    );
    return ToastHandle._(entry, view);
  }
}

/// Тост из `BuildContext` — короткая запись для мест, где мессенджер не нужен
/// отдельно.
void showToast(
  BuildContext context,
  String text, {
  ToastKind kind = ToastKind.info,
  ToastAction? action,
}) => ScaffoldMessenger.of(context).toast(text, kind: kind, action: action);

/// Состояние живого тоста — то, что [ToastHandle] меняет на лету.
class ToastView {
  const ToastView({
    required this.text,
    this.kind = ToastKind.info,
    this.busy = true,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final ToastKind kind;

  /// Вертушка вместо значка.
  final bool busy;

  /// Доля 0..1 для нижней полосы; `null` — полосы прогресса нет.
  final double? progress;

  /// Полоса-таймер на столько; `null` — не отсчитывать.
  final Duration? barDuration;

  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Ручка живого тоста: пока идёт работа — [update], в конце — [finish].
class ToastHandle {
  ToastHandle._(this._entry, this._view) {
    unawaited(_entry.closed.then((_) => _closed = true));
  }

  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _entry;
  final ValueNotifier<ToastView> _view;
  bool _closed = false;
  Timer? _timer;

  /// Обновить текст/прогресс, не пересоздавая тост.
  void update(String text, {double? progress}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      progress: progress,
      actionLabel: _view.value.actionLabel,
      onAction: _view.value.onAction,
    );
  }

  /// Подменить содержимое итогом: вертушка уходит, появляется значок вида и
  /// полоса отсчёта, через 2.4с тост гаснет сам.
  void finish(String text, {ToastKind kind = ToastKind.success}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      kind: kind,
      busy: false,
      barDuration: _finished,
    );
    _timer?.cancel();
    _timer = Timer(_finished, close);
  }

  void close() {
    _timer?.cancel();
    if (_closed) return;
    _closed = true;
    _entry.close();
  }
}

/// Общая часть: показать произвольный виджет как снекбар без собственного вида.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(
  ScaffoldMessengerState messenger, {
  required Widget child,
  required Duration duration,
}) => messenger.showSnackBar(
  SnackBar(
    content: child,
    duration: duration,
    // Весь вид — на карточке: у самого снекбара ни фона, ни тени, ни отступов.
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    dismissDirection: DismissDirection.horizontal,
    shape: const RoundedRectangleBorder(),
  ),
);

class _LiveToast extends StatelessWidget {
  const _LiveToast({required this.view});

  final ValueListenable<ToastView> view;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: view,
    builder: (_, v, _) => BloomToastCard(
      text: v.text,
      kind: v.kind,
      busy: v.busy,
      progress: v.progress,
      barDuration: v.barDuration,
      actionLabel: v.actionLabel,
      onAction: v.onAction,
    ),
  );
}

/// Сама плашка: стеклянная капсула, значок вида с кольцом-отсчётом, текст,
/// кнопка-пилюля и — только у долгих работ — полоса прогресса по низу.
class BloomToastCard extends StatelessWidget {
  const BloomToastCard({
    super.key,
    required this.text,
    this.kind = ToastKind.info,
    this.busy = false,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.hasAction = false,
    this.onAction,
  });

  final String text;
  final ToastKind kind;
  final bool busy;
  final double? progress;
  final Duration? barDuration;
  final String? actionLabel;

  /// Кнопка есть, но своей подписи у неё нет — подставится «Отменить».
  final bool hasAction;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = kindColor(kind, t);
    final label = actionLabel ?? (hasAction ? context.l.commonUndo : null);
    final action = label != null && onAction != null;

    return _Pop(
      child: Align(
        // Ширина по содержимому, как inline-flex на ПК: короткому «Трек удалён»
        // незачем растягиваться во весь экран. Потолок — чтобы на планшете
        // капсула не расползлась во всю строку.
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          // Своя группа: тост всплывает поверх страницы и её баров, к их
          // снимку подложки ему присоединяться нельзя (см. `glass.dart`).
          child: GlassGroup(
            child: GlassBox(
              // Поверхность всплывающая — стекло берём то же, что у шторок и
              // меню, а не то, что у блоков страницы.
              overlay: true,
              // `pill`, а не `card`: на тёмной теме `card` — это цвет фона,
              // и капсула читалась бы только по рамке.
              color: t.pill,
              shape: StadiumBorder(
                side: BorderSide(color: t.ovlLine2, width: 1),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      8,
                      action ? 8 : 18,
                      // Место под полосу прогресса — только когда она есть.
                      progress == null ? 8 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Badge(
                          color: color,
                          kind: kind,
                          busy: busy,
                          duration: barDuration,
                        ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            text,
                            style: bloomText(
                              size: 13.5,
                              weight: 500,
                              color: t.text,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (action) ...[
                          const SizedBox(width: 10),
                          BloomTag(
                            text: label,
                            color: t.accent,
                            onTap: onAction!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (progress != null)
                    Positioned(
                      // Отступы по краям обязательны: у капсулы низ сужен
                      // скруглением, полоса во всю ширину обрезалась бы.
                      left: 18,
                      right: 18,
                      bottom: 5,
                      child: BloomBar(
                        value: progress!,
                        color: color,
                        track: color.withValues(alpha: 0.14),
                        height: 3,
                        animated: const Duration(milliseconds: 250),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Появление: тост не просто выезжает снекбаром, а всплывает — проявляется и
/// чуть подрастает от нижнего края.
///
/// Живёт отдельным виджетом со своим состоянием: `_LiveToast` перестраивает
/// карточку на каждом обновлении текста, и всплытие не должно играть заново.
class _Pop extends StatefulWidget {
  const _Pop({required this.child});

  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    child: ScaleTransition(
      scale: Tween(
        begin: 0.92,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
      alignment: Alignment.bottomCenter,
      child: widget.child,
    ),
  );
}

/// Цвета видов — те же значения, что в `search-misc.css`; `info` берёт акцент
/// темы, а `error` — общий красный опасного, чтобы в приложении был ровно один
/// красный (десктопный `#E0494A` от него почти неотличим).
Color kindColor(ToastKind kind, BloomTokens t) => switch (kind) {
  ToastKind.info => t.accent,
  ToastKind.success => const Color(0xFF2FBF6C),
  ToastKind.warn => const Color(0xFFE0A52E),
  ToastKind.error => t.danger,
};

/// Значок вида в круге своего цвета, а вокруг — кольцо обратного отсчёта.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.kind,
    required this.busy,
    this.duration,
  });

  final Color color;
  final ToastKind kind;
  final bool busy;

  /// Сколько тосту осталось жить; `null` — кольца нет (идёт работа или тост
  /// висит до `close()`).
  final Duration? duration;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (duration != null)
          Positioned.fill(
            child: _Ring(color: color, duration: duration!),
          ),
        TintCircle(
          size: 27,
          color: color.withValues(alpha: 0.16),
          child: busy
              ? BloomSpinner(size: 15, color: color)
              // У «успеха» голая галочка, а не `checkCircle`: значок и так
              // лежит в круге, круг в круге читался бы мишенью (на ПК то же —
              // `CheckBare`).
              : kind == ToastKind.success
              ? BloomIcon(Bi.check, size: 18, color: color)
              : BloomIcon(_glyph(kind), size: 17, color: color),
        ),
      ],
    ),
  );

  static BloomGlyph _glyph(ToastKind kind) => switch (kind) {
    ToastKind.info => Bi.infoCircle,
    ToastKind.warn => Bi.danger,
    ToastKind.error => Bi.dangerCircle,
    ToastKind.success => Bi.check,
  };
}

/// Кольцо обратного отсчёта вокруг значка: дуга утекает по часовой за время
/// жизни тоста. Старт отложен на въезд — таймер снекбара тоже начинается только
/// по концу анимации появления, иначе кольцо ушло бы вперёд отсчёта.
class _Ring extends StatefulWidget {
  const _Ring({required this.color, required this.duration});

  final Color color;
  final Duration duration;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(_Ring old) {
    super.didUpdateWidget(old);
    // Итог подменил содержимое — отсчёт начинается заново.
    if (widget.duration != old.duration) _run();
  }

  void _run() {
    _delay?.cancel();
    _c
      ..duration = widget.duration
      ..value = 0;
    _delay = Timer(_enter, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(
      painter: _RingPainter(color: widget.color, left: 1 - _c.value),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.left});

  final Color color;

  /// Доля оставшегося времени, 1 → 0.
  final double left;

  static const double _width = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - _width) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round;

    // Дорожка кольца: тот же цвет, но еле заметный — по ней видно, сколько
    // времени уже утекло.
    canvas.drawCircle(
      center,
      radius,
      paint..color = color.withValues(alpha: 0.14),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * left.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.left != left || old.color != color;
}
