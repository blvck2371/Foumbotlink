import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/controllers/compose_controller.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  group('reconnaissance photo / vidéo', () {
    test('par extension quand le type manque (Android)', () {
      expect(ComposeController.isVideoFile(XFile('/tmp/VID_2026.mp4')), isTrue);
      expect(ComposeController.isVideoFile(XFile('/tmp/clip.MOV')), isTrue);
      expect(ComposeController.isVideoFile(XFile('/tmp/IMG_1.jpg')), isFalse);
    });

    test('par type MIME quand il est fourni (web, adresse blob:)', () {
      expect(
        ComposeController.isVideoFile(
          XFile('blob:https://foumbotlink.web.app/1', mimeType: 'video/mp4'),
        ),
        isTrue,
      );
      expect(
        ComposeController.isVideoFile(
          XFile('blob:https://foumbotlink.web.app/2', mimeType: 'image/png'),
        ),
        isFalse,
      );
    });
  });
}
