import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/spacing.dart';

/// Bottom sheet that asks the user where to get the receipt image from.
/// Returns the picked [XFile], or `null` if the user cancels.
///
/// `image_picker` itself handles camera + photo-library permission
/// prompts on iOS/Android — we don't need `permission_handler` here.
Future<XFile?> showReceiptPicker(BuildContext context) {
  return showModalBottomSheet<XFile?>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => const _ReceiptPickerSheet(),
  );
}

class _ReceiptPickerSheet extends StatelessWidget {
  const _ReceiptPickerSheet();

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(source: source, imageQuality: 80);
      if (!context.mounted) return;
      Navigator.of(context).pop(file);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop(null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access the camera or library')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Scan a receipt', style: theme.textTheme.titleMedium),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => _pick(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => _pick(context, ImageSource.gallery),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(context).pop(null),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
