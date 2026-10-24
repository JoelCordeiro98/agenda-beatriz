import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PickedPhoto {
  final Uint8List bytes;
  final String mimeType;
  const PickedPhoto(this.bytes, this.mimeType);
}

/// Pergunta câmera ou galeria e devolve a foto já reduzida (ou null).
Future<PickedPhoto?> pickPhoto(BuildContext context) async {
  final choice = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return null;
  final file = await ImagePicker().pickImage(
    source: choice,
    maxWidth: 1200,
    maxHeight: 1200,
    imageQuality: 80,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final mime = file.mimeType ?? 'image/jpeg';
  return PickedPhoto(
    bytes,
    ['image/png', 'image/webp'].contains(mime) ? mime : 'image/jpeg',
  );
}
