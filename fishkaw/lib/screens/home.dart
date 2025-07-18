// ignore_for_file: unused_import, depend_on_referenced_packages, non_constant_identifier_names

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
// 1. Import the photo_manager package
import 'package:photo_manager/photo_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedNavIndex = 0;

  // 2. State variables for gallery images and loading status
  List<AssetEntity> _galleryImages = [];
  bool _isLoading = true;


  // 3. Fetch gallery images when the widget is initialized
  @override
  void initState() {
    super.initState();
    _fetchGalleryImages();
  }

  // 4. Logic to request permission and load images from the device gallery
  Future<void> _fetchGalleryImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      // Permission granted
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      if (albums.isNotEmpty) {
        final List<AssetEntity> recentImages = await albums.first.getAssetListPaged(
          page: 0,
          size: 10, // Fetch 10 recent images
        );
        setState(() {
          _galleryImages = recentImages;
          _isLoading = false;
        });
      }
    } else {
      // Permission denied
      setState(() {
        _isLoading = false;
      });
      // Optionally, show a message to the user
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo library access was denied.')),
      );
    }
  }


  void _openGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: ${pickedFile.name}')),
      );
    }
  }

  void _scanFish() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Launching Scan...')),
    );
  }

  void _goToFAQ() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening FAQs...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Right-side Fish Image
            Positioned(
              top: 0,
              right: -50,
              child: Image.asset(
                'assets/images/fish_koi.png', // Ensure this path is correct
                width: 250,
                fit: BoxFit.contain,
              ),
            ),

            // Main Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Top Row (Help icon and avatar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _goToFAQ,
                        child: const Icon(Icons.help_outline, color: Colors.white, size: 28),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const CircleAvatar(
                            // Make sure you have an avatar image in assets
                            backgroundImage: AssetImage('assets/images/avatar.jpg'),
                            radius: 20,
                          ),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '2',
                                style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Gradient Title - Fixed
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF2BFFC4), Colors.white],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      'Fish Fresh',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        // This color is crucial for the shader to work
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Hi Aziz,',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 250, // Constrain width to avoid text overlapping the fish
                    child: Text(
                      'This app helps you check the freshness of fish in seconds. Simply snap a photo, and our AI analyzes color, texture, and key features to give you an instant freshness score.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Recents Section
                  _buildRecents(),
                  const SizedBox(height: 20),
                  // Usage Status Section
                  _buildUsageStatus(),
                  const Spacer(),
                ],
              ),
            ),
             // Custom Bottom Navigation
            _buildBottomNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recents', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Today', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 180, // Adjust height as needed
          // 5. Update GridView to use the dynamic list of images
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _galleryImages.length + 1, // +1 for the gallery button
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // First item is the button to open the full gallery
                      return GestureDetector(
                        onTap: _openGallery,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.photo_camera_back_outlined, color: Colors.white70, size: 40),
                        ),
                      );
                    }
                    // Display recent images from the phone's gallery
                    final AssetEntity assetEntity = _galleryImages[index - 1];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // Use AssetEntityImage to efficiently display thumbnails
                      child: AssetEntityImage(
                        assetEntity,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(200), // Adjust quality
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                           return const Icon(Icons.error, color: Colors.red);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUsageStatus() {
    // Mock data for the chart bars
    final List<double> usageData = [0.4, 0.5, 0.8, 0.4, 0.6, 0.5, 0.9];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Usage Status', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total spend', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                const SizedBox(height: 4),
                const Text('3 hrs 2 m', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
             Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total hours', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                const SizedBox(height: 4),
                const Text('32h', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
             Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFF2BFFC4),
                  borderRadius: BorderRadius.circular(20),
                ),
              child: const Text('2 hrs', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Bar Chart
        SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(usageData.length, (index) {
              return Container(
                width: 20,
                height: 60 * usageData[index],
                decoration: BoxDecoration(
                  color: index == 2 ? const Color(0xFF2BFFC4) : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Home and History Buttons
            Container(
              height: 55,
              width: 130,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavIcon(Icons.home, 0),
                  _buildNavIcon(Icons.history, 1),
                ],
              ),
            ),
            // Scan Button
            GestureDetector(
              onTap: _scanFish,
              child: Container(
                height: 55,
                width: 55,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: Colors.black, size: 30),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    bool isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNavIndex = index;
        });
      },
      child: Container(
        height: 45,
        width: 45,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isSelected ? Colors.white : Colors.black, size: 28),
      ),
    );
  }
  
  AssetEntityImage(AssetEntity assetEntity, {required bool isOriginal, required ThumbnailSize thumbnailSize, required BoxFit fit, required Icon Function(dynamic context, dynamic error, dynamic stackTrace) errorBuilder}) {}
}