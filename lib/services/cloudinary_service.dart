import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class MediaUploadException implements Exception {
  final String message;

  const MediaUploadException(this.message);

  @override
  String toString() => message;
}

/// Uploads product photos/videos to Cloudinary's free tier and returns
/// a permanent, publicly-viewable URL — used instead of Firebase
/// Storage so the app doesn't require the Blaze billing plan.
///
/// TODO: replace these two placeholder values with your real
/// Cloudinary "Cloud name" and the unsigned upload preset name you
/// created in the Cloudinary dashboard (Settings -> Upload -> Upload
/// presets). Neither value is a secret — that's the point of an
/// unsigned preset — so it's fine for them to live directly in the
/// app like this.
class CloudinaryService {
  static const String cloudName = "oaaryklt";
  static const String uploadPreset = "craft_of_love_unsigned";
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const Duration uploadTimeout = Duration(seconds: 90);

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };
  static const Set<String> _videoExtensions = {'.mp4', '.mov', '.m4v', '.webm'};

  static bool get isConfigured =>
      cloudName != "YOUR_CLOUD_NAME" && uploadPreset != "YOUR_UPLOAD_PRESET";

  /// Checks the media type, extension, and size before any network request.
  static void validateMetadata({
    required String filePath,
    required int byteLength,
    required String resourceType,
  }) {
    final extension = path.extension(filePath).toLowerCase();
    final isImage = resourceType == 'image';
    final isVideo = resourceType == 'video';

    if (!isImage && !isVideo) {
      throw const MediaUploadException('Unsupported media type.');
    }
    if (byteLength <= 0) {
      throw const MediaUploadException('The selected file is empty.');
    }

    final allowedExtensions = isImage ? _imageExtensions : _videoExtensions;
    if (!allowedExtensions.contains(extension)) {
      throw MediaUploadException(
        isImage
            ? 'Choose a JPG, PNG, WebP, HEIC, or HEIF image.'
            : 'Choose an MP4, MOV, M4V, or WebM video.',
      );
    }

    final maximumBytes = isImage ? maxImageBytes : maxVideoBytes;
    if (byteLength > maximumBytes) {
      throw MediaUploadException(
        isImage
            ? 'Images must be 10 MB or smaller.'
            : 'Videos must be 100 MB or smaller.',
      );
    }
  }

  static Future<void> validateFile(
    File file, {
    required String resourceType,
  }) async {
    if (!await file.exists()) {
      throw const MediaUploadException(
        'The selected file is no longer available.',
      );
    }
    validateMetadata(
      filePath: file.path,
      byteLength: await file.length(),
      resourceType: resourceType,
    );
  }

  /// Uploads [file] (image or video) and returns its Cloudinary URL.
  /// [resourceType] should be "image" or "video".
  static Future<String> upload(
    File file, {
    required String resourceType,
  }) async {
    await validateFile(file, resourceType: resourceType);

    if (!isConfigured) {
      throw const MediaUploadException(
        "Cloudinary isn't configured yet — set cloudName and uploadPreset "
        "in lib/services/cloudinary_service.dart.",
      );
    }

    final uri = Uri.parse(
      "https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload",
    );

    final request = http.MultipartRequest("POST", uri)
      ..fields["upload_preset"] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath("file", file.path));

    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request.send().timeout(uploadTimeout);
    } on TimeoutException {
      throw const MediaUploadException(
        'The upload timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const MediaUploadException(
        'Could not upload the file. Check your connection and try again.',
      );
    }
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaUploadException(
        'The media service rejected the upload (${response.statusCode}). '
        'Please try another file.',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MediaUploadException(
        'The media service returned an invalid response. Please try again.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MediaUploadException(
        'The media service returned an invalid response. Please try again.',
      );
    }
    final url = decoded["secure_url"] as String?;
    final parsedUrl = url == null ? null : Uri.tryParse(url);

    if (parsedUrl == null ||
        parsedUrl.scheme != 'https' ||
        parsedUrl.host != 'res.cloudinary.com') {
      throw const MediaUploadException(
        'The media service did not return a valid secure URL.',
      );
    }

    return parsedUrl.toString();
  }
}
