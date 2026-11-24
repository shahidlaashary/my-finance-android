import 'package:flutter/material.dart';

/// Opt-in form dropdown whose popup width matches its rendered field width.
class WidthMatchedDropdownFormField<T> extends FormField<T> {
  WidthMatchedDropdownFormField({
    super.key,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    required InputDecoration decoration,
    bool isExpanded = false,
    Widget? hint,
    Widget? disabledHint,
    Widget? icon,
    Color? dropdownColor,
    double? menuMaxHeight,
    BorderRadius? borderRadius,
    int elevation = 8,
    FormFieldValidator<T>? validator,
    FormFieldSetter<T>? onSaved,
    bool enabled = true,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) : super(
          initialValue: value,
          validator: validator,
          onSaved: onSaved,
          enabled: enabled,
          autovalidateMode: autovalidateMode,
          builder: (fieldState) => LayoutBuilder(
            builder: (context, constraints) {
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
                            onChanged(nextValue);
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
                    menuWidth: constraints.maxWidth,
                  ),
                ),
              );
            },
          ),
        );
}
