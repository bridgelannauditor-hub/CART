import 'package:craft_of_love/services/cloudinary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudinaryService media validation', () {
    test('accepts supported image and video metadata', () {
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'product.JPG',
          byteLength: CloudinaryService.maxImageBytes,
          resourceType: 'image',
        ),
        returnsNormally,
      );
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'demo.mp4',
          byteLength: CloudinaryService.maxVideoBytes,
          resourceType: 'video',
        ),
        returnsNormally,
      );
    });

    test('rejects mismatched extensions', () {
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'renamed.exe',
          byteLength: 1024,
          resourceType: 'image',
        ),
        throwsA(isA<MediaUploadException>()),
      );
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'photo.jpg',
          byteLength: 1024,
          resourceType: 'video',
        ),
        throwsA(isA<MediaUploadException>()),
      );
    });

    test('rejects empty and oversized files', () {
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'photo.jpg',
          byteLength: 0,
          resourceType: 'image',
        ),
        throwsA(isA<MediaUploadException>()),
      );
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'demo.mp4',
          byteLength: CloudinaryService.maxVideoBytes + 1,
          resourceType: 'video',
        ),
        throwsA(isA<MediaUploadException>()),
      );
    });

    test('rejects unknown resource types', () {
      expect(
        () => CloudinaryService.validateMetadata(
          filePath: 'photo.jpg',
          byteLength: 1024,
          resourceType: 'raw',
        ),
        throwsA(isA<MediaUploadException>()),
      );
    });
  });
}
