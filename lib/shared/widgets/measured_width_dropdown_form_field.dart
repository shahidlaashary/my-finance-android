import 'package:flutter/material.dart';

/// A form dropdown that measures its available field width before building
/// the popup, so the popup width is tied to the actual field constraints.
class MeasuredWidthDropdownFormField<T> extends StatelessWidget {
  const MeasuredWidthDropdownFormField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.isExpanded = false,
    this.hint,
    this.disabledHint,
    this.icon,
    this.dropdownColor,
    this.menuMaxHeight,
    this.borderRadius,
    this.elevation = 8,
    this.validator,
    this.onSaved,
    this.enabled = true,
    this.autovalidateMode = AutovalidateMode.disabled,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  final Widget? hint;
  final Widget? disabledHint;
  final Widget? icon;
  final Color? dropdownColor;
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;
  final int elevation;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;
  final bool enabled;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : null;

        return FormField<T>(
          initialValue: value,
          validator: validator,
          onSaved: onSaved,
          enabled: enabled,
          autovalidateMode: autovalidateMode,
          builder: (fieldState) {
            final fieldDecoration = decoration.copyWith(
              enabled: enabled,
              errorText: fieldState.errorText,
              isDense: decoration.isDense ?? true,
            );

            return InputDecorator(
              decoration: fieldDecoration,
              isEmpty: fieldState.value == null && hint == null,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: fieldState.value,
                  items: items,
                  onChanged: enabled && onChanged != null
                      ? (nextValue) {
                          fieldState.didChange(nextValue);
                          onChanged!(nextValue);
                        }
                      : null,
                  isExpanded: isExpanded,
                  isDense: true,
                  hint: hint,
                  disabledHint: disabledHint,
                  icon: icon,
                  dropdownColor: dropdownColor,
                  menuMaxHeight: menuMaxHeight,
                  borderRadius: borderRadius,
                  elevation: elevation,
                  menuWidth: fieldWidth,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
