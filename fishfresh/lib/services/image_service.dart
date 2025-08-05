import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class ImageService {
  /// Picks an image from the gallery and saves it locally.
  /// Returns the full path to the saved image.
  static Future<String?> pickAndSaveImageLocally() async {
    final picker = ImagePicker();

    // Step 1: Pick image from gallery
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return null;

    // Step 2: Get app's document directory
    final Directory appDir = await getApplicationDocumentsDirectory();

    // Step 3: Create a unique filename
    final String fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Step 4: Create the full file path
    final String savedImagePath = join(appDir.path, fileName);

    // Step 5: Copy the picked image to the app directory
    await File(pickedFile.path).copy(savedImagePath);

    // Step 6: Return the new local path
    return savedImagePath;
  }
}
