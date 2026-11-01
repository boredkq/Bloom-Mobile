/// Шапка подстраницы настроек: круглая «назад» и название широкой пилюлей.
///
/// Пилюля тянется на всю оставшуюся ширину, название по центру — так раздел
/// читается как заголовок экрана, а не как подпись рядом с кнопкой.
///
/// Рядом — [SubPage], каркас такой страницы целиком: шапка прибита, листается
/// только содержимое под ней.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';

class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleIconButton(icon: Bi.arrowLeft, onTap: onBack),
        const SizedBox(width: 10),
        Expanded(
          child: GlassBox(
            // Скруглена полностью, а не на радиус темы: рядом круглая кнопка,
            // и эти двое должны читаться одной парой.
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: kHeaderControl,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // На кегль строки списка (`titleMedium`) название в выросшей
                  // пилюле не тянет: вокруг него слишком много воздуха, и шапка
                  // читается пустой. Правка местная — общий стиль держит строки
                  // треков и подписи карточек, ему расти нельзя.
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: kHeaderTitleSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Капсовый заголовок группы на подстранице настроек.
///
/// Цвет — тот же `text2`, что у групп в корневых «Настройках»: общий
/// `labelSmall` приглушён до `muted`, и после перехода с корневого списка
/// заголовки заметно тускнели.
class SettingsCaption extends StatelessWidget {
  const SettingsCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: context.bloom.text2),
  );
}

/// Группа строк настроек: один тёмный контейнер, внутри строки, отбитые тонкой
/// линией.
///
/// Связанные строки стоят вместе, а не отдельными карточками с зазором:
/// заголовок группы над ними и так говорит, что это одно про одно, а колонка
/// одинаковых плашек читалась списком без начала и конца.
///
/// [dividerInset] — отступ линии слева: она должна начинаться под ТЕКСТОМ
/// строки, а не под её краем, поэтому в списках со значком слева он больше.
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.rows,
    this.dividerInset = 16,
  });

  final List<Widget> rows;
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassBox(
      // Скруглена заметнее плашек поменьше: карточка группы во всю ширину и в
      // несколько строк, и на такой коробке радиус темы читается почти прямым
      // углом. Доля, а не прибавка: радиус 0 в «Интерфейсе» должен оставлять
      // группу квадратной.
      borderRadius: BorderRadius.circular(t.radius * 1.3),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) GroupDivider(indent: dividerInset),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The line between rows of a group, from where their text starts. Half of the
/// usual line: the plate already groups them, this only hints.
class GroupDivider extends StatelessWidget {
  const GroupDivider({super.key, required this.indent});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final line = context.bloom.ovlLine;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(height: 1, color: line.withValues(alpha: line.a * 0.5)),
    );
  }
}

/// Каркас подстраницы настроек: [SubPageHeader] прибит сверху, скролл живёт
/// только в содержимом под ним.
///
/// Так «назад» и название раздела всегда под пальцем: раньше шапка ехала
/// первым элементом общего списка и уползала за край с первым же движением.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
  });

  final String title;
  final VoidCallback onBack;

  /// Содержимое страницы — дети скроллящегося списка под шапкой.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SubPageHeader(title: title, onBack: onBack),
          ),
          // Часть просвета — распоркой, а не отступом списка: она остаётся на
          // месте при скролле, и содержимое обрезается не по самому краю
          // пилюли, а на этот зазор ниже. Вплотную к ней карточки касаются
          // некрасиво.
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              // Вместе с распоркой сверху выходят прежние 22 — просвет под
              // шапкой в покое не изменился. Снизу добавлены бары каркаса:
              // они плавают над содержимым.
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                24 + bottomBarsInset(context),
              ),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
