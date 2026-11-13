import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/receipt_scanner.dart';
import '../services/receipt_store.dart';
import '../utils/dimens.dart';

/// A transaction's receipt photo in an edit form: a thumbnail to open full
/// screen and a button to remove it, or a button to attach one.
class ReceiptPhotoRow extends StatelessWidget {
  /// The stored photo, if the row has one.
  final String? attachment;

  /// A photo just picked, not stored yet; shown in place of [attachment].
  final String? newPhoto;
  final ValueChanged<String> onPicked;
  final VoidCallback onRemove;

  const ReceiptPhotoRow({
    super.key,
    required this.attachment,
    required this.newPhoto,
    required this.onPicked,
    required this.onRemove,
  });

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final path = await ReceiptScanner.pickPhoto(source);
    if (path != null) onPicked(path);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = newPhoto != null || attachment != null;
    if (!hasPhoto) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: const Text('Attach receipt photo'),
          onPressed: () => _pick(context),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          FutureBuilder<File>(
            future: newPhoto != null
                ? Future.value(File(newPhoto!))
                : ReceiptStore.fileFor(attachment!),
            builder: (context, snap) {
              final file = snap.data;
              return InkWell(
                onTap:
                    file == null ? null : () => showReceiptPhoto(context, file),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: file == null
                      ? const SizedBox(width: 48, height: 48)
                      : Image.file(file,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.broken_image_outlined))),
                ),
              );
            },
          ),
          const SizedBox(width: Space.md),
          const Expanded(child: Text('Receipt photo')),
          TextButton(
            onPressed: () => _pick(context),
            child: const Text('Replace'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove photo',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Shows a receipt photo full screen, zoomable.
Future<void> showReceiptPhoto(BuildContext context, File file) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Receipt'),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(file,
                  errorBuilder: (_, __, ___) => const Text(
                      'The photo is no longer on this device',
                      style: TextStyle(color: Colors.white))),
            ),
          ),
        ),
      ),
    );
