/// Подтверждение необратимого — шторкой с красной кнопкой, а не системным
/// `confirm()`, как на ПК: по строке в списке на телефоне промахнуться легко,
/// по кнопке в шторке нет. Один вид на все места: сбросы в «Системе», очистка
/// в «Хранилище», «Отключить» у компьютера.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';

/// Шторка «значок, что будет, красная кнопка»; `true` — нажали кнопку.
Future<bool> confirmDanger(
  BuildContext context, {
  required BloomGlyph icon,
  required String title,
  required String body,
  required String button,
}) async =>
    await showBloomSheetChild<bool>(
      context: context,
      child: DangerConfirmBody(
        icon: icon,
        title: title,
        body: body,
        button: button,
      ),
    ) ==
    true;

/// Тело шторки: крупный значок на красном круге, название, что произойдёт, и
/// [DangerSheetButton].
class DangerConfirmBody extends StatelessWidget {
  const DangerConfirmBody({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
  });

  final BloomGlyph icon;
  final String title;
  final String body;
  final String button;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        children: [
          TintCircle(
            size: 72,
            color: t.danger.withValues(alpha: 0.12),
            child: BloomIcon(icon, size: 28, color: t.danger),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: theme.titleLarge),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodySmall?.copyWith(color: t.text2),
          ),
          const SizedBox(height: 20),
          DangerSheetButton(label: button),
        ],
      ),
    );
  }
}

/// Красная кнопка во всю ширину шторки: закрывает её с `true`. Погашенная
/// ([enabled] = false) — когда делать нечего (пустой кеш).
class DangerSheetButton extends StatelessWidget {
  const DangerSheetButton({
    super.key,
    required this.label,
    this.enabled = true,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => BloomButton(
    label: label,
    tone: ButtonTone.danger,
    pill: false,
    height: 54,
    onTap: enabled ? () => Navigator.of(context).pop(true) : null,
  );
}
