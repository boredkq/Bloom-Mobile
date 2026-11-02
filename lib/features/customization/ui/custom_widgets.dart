/// Shared for customization: page frame, context icons, the sheet's fields and
/// add form, an empty list caption. Its own frame rather than [SubPage], which
/// scrolls all content as one list: here only the tab's grid scrolls, with
/// tiles and tabs staying put.
library;

import 'package:flutter/material.dart';

import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import '../custom_store.dart';
import '../../../shared/ui/atoms.dart';

/// A context's icon: for the page's tiles, the picture sheet's rows
/// and the badge of where a picture is used.
BloomGlyph customCtxIcon(CustomCtx ctx) => switch (ctx) {
  CustomCtx.bg => Bi.galleryWide,
  CustomCtx.cover => Bi.gallery,
  CustomCtx.slider => Bi.sliderHorizontal,
};

/// Input in a sheet, just like [SheetField]: a wide field and an accent tick
/// appearing with text. Returns the value through `Navigator.pop`.
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

/// Sheet under customization's plus: an input ([SheetTextField]) and a second
/// way to add below it, Attach photo for the library and Import for presets.
/// Closes with the entered string, or `true` if the item below was picked.
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

  /// Item under the field.
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
