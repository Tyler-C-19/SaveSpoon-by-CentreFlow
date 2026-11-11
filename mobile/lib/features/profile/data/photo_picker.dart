import 'package:image_picker/image_picker.dart';

enum PhotoSource { gallery, camera }

class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.filename});

  final List<int> bytes;
  final String filename;
}

abstract class PhotoPicker {
  Future<PickedPhoto?> pick(PhotoSource source);
}

class DevicePhotoPicker implements PhotoPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    // Shrunk on the phone first so uploads stay well under the 5 MB limit.
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    return PickedPhoto(bytes: await file.readAsBytes(), filename: file.name);
  }
}
