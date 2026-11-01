/// Общее для «Кастомизации»: каркас страницы, значки контекстов, поля и
/// форма добавления в шторке, подпись пустого списка.
///
/// Каркас свой, а не [SubPage]: там всё содержимое едет одним списком, а здесь
/// листается только сетка вкладки — плитки и вкладки над ней стоят на месте.
library;

import 'package:flutter/material.dart';

import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import '../custom_store.dart';
import '../../../shared/ui/atoms.dart';

/// A context's icon, the PC's: for the page's tiles, the picture sheet's rows
/// and the badge of where a picture is used.
BloomGlyph customCtxIcon(CustomCtx ctx) => switch (ctx) {
  CustomCtx.bg => Bi.galleryWide,
  CustomCtx.cover => Bi.gallery,
  CustomCtx.slider => Bi.sliderHorizontal,
};

/// Поле ввода в шторке — ровно то же, что у «Создать плейлист» ([SheetField]):
/// широкое поле и акцентная галочка, которая появляется вместе с текстом.
///
/// Возвращает введённое значение через `Navigator.pop`.
class SheetTextField extends StatefulWidget {
  const SheetTextField({
    super.key,
    required this.hint,
    this.initial = '',
    this.maxLength,
  });

  final String hint;
  final String initial;
  final int? maxLength;

  @override
  State<SheetTextField> createState() => _SheetTextFieldState();
}

class _SheetTextFieldState extends State<SheetTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => SheetField(
    controller: _controller,
    hint: widget.hint,
    autofocus: true,
    maxLength: widget.maxLength,
    onChanged: (_) => setState(() {}),
    onSubmit: _submit,
  );
}

/// Шторка под плюсиком «Кастомизации»: поле ввода ([SheetTextField]) и под
/// ним второй способ добавить — «Приложить фото» у библиотеки, «Импорт» у
/// пресетов.
///
/// Закрывается введённой строкой или `true`, если выбрали пункт под полем.
class SheetAddForm extends StatelessWidget {
  const SheetAddForm({
    super.key,
    required this.hint,
    required this.icon,
    required this.label,
    this.maxLength,
  });

  final String hint;
  final int? maxLength;

  /// Пункт под полем.
  final BloomGlyph icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SheetTextField(hint: hint, maxLength: maxLength),
      SheetPickRow(icon: icon, label: label),
    ],
  );
}

/// The item under the field of an adding sheet: closes it with `true`.
class SheetPickRow extends StatelessWidget {
  const SheetPickRow({super.key, required this.icon, required this.label});

  final BloomGlyph icon;
  final String label;

  @override
  Widget build(BuildContext context) => SheetPanel(
    children: [
      SheetRow(
        icon: icon,
        label: label,
        onTap: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

/// A pane of tiles in two columns, or a note when there are none.
class CustomPane extends StatelessWidget {
  const CustomPane({
    super.key,
    required this.empty,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String empty;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return Center(
        child: CenterNote(
          empty,
          padding: const EdgeInsets.symmetric(horizontal: 40),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 8 + bottomBarsInset(context)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 4 / 3,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
