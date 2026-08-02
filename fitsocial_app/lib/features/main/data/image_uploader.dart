import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Thrown when an image upload cannot be completed.
class ImageUploadException implements Exception {
  const ImageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uploads processed images to Cloud Storage.
///
/// Deliberately knows nothing about resizing or compression — callers pass an
/// already-optimized file from `image_pipeline.dart`. Keeping the two apart
/// means the geometry logic can be unit-tested without a Firebase instance.
class ImageUploader {
  ImageUploader({FirebaseStorage? storage, Uuid? uuid})
      : _storage = storage ?? FirebaseStorage.instance,
        _uuid = uuid ?? const Uuid();

  final FirebaseStorage _storage;
  final Uuid _uuid;

  /// Matches the `posts/{userId}/{fileName}` rule in storage.rules, which
  /// permits writes only where the path segment equals the caller's uid.
  static const String _postsRoot = 'posts';

  /// A slow connection shouldn't hang the compose screen forever.
  static const Duration _uploadTimeout = Duration(seconds: 120);

  /// Uploads [optimizedFile] to `posts/{userId}/{uuid}.jpg` and returns its
  /// download URL.
  ///
  /// A fresh UUID per upload means a re-post never overwrites an earlier image
  /// and the object name can't be guessed from the user id.
  Future<String> uploadPostImage(File optimizedFile, String userId) async {
    if (userId.isEmpty) {
      throw const ImageUploadException('Cannot upload without a user id.');
    }
    if (!optimizedFile.existsSync()) {
      throw const ImageUploadException('Processed image no longer exists.');
    }

    final reference =
        _storage.ref().child('$_postsRoot/$userId/${_uuid.v4()}.jpg');

    try {
      final task = reference.putFile(
        optimizedFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await task.timeout(
        _uploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Image upload timed out after ${_uploadTimeout.inSeconds} seconds.',
        ),
      );

      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (error) {
      // Surfaces the actionable cases rather than a raw plugin error — an
      // unauthorized result almost always means storage.rules is undeployed.
      throw ImageUploadException(
        switch (error.code) {
          'unauthorized' =>
            'Not allowed to upload this image. Check that Storage rules are deployed.',
          'canceled' => 'Upload was cancelled.',
          'retry-limit-exceeded' =>
            'Upload failed — the connection was too slow or dropped.',
          _ => 'Upload failed: ${error.message ?? error.code}',
        },
      );
    }
  }
}
