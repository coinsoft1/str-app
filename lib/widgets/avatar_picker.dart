// lib/widgets/avatar_picker.dart
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class AvatarPickerGrid extends StatelessWidget {
  final String selectedAvatar;
  final ValueChanged<String> onAvatarSelected;

  const AvatarPickerGrid({
    super.key,
    required this.selectedAvatar,
    required this.onAvatarSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: SettingsService.presetAvatars.map((avatar) {
        final isSelected = selectedAvatar == avatar;

        return Semantics(
          label: 'Select $avatar avatar',
          button: true,
          child: InkWell(
            onTap: () => onAvatarSelected(avatar),
            borderRadius: BorderRadius.circular(16),
            child: Tooltip(
              message: avatar,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    avatar,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}