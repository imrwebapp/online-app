import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PostScreen extends StatelessWidget {
  const PostScreen({Key? key}) : super(key: key);

  final String enrollUrl = 'https://forms.gle/tzYpLKUeCuUe8XiY9';
  final String umrahUrl = 'https://forms.gle/MUnTBTxxtdu4BQV76';

  final String tiktokUrl =
      'https://www.tiktok.com/@qariabdulmateenshaheen?_r=1&_t=ZN-92A7VklRPs6';
  final String facebookUrl = 'https://www.facebook.com/share/1ME5cLw3kM/';
  final String instagramUrl =
      'https://www.instagram.com/qariabdulmateenshaheen?igsh=ZnRqNGljejBneTM3';

  // WhatsApp & Email
  final String whatsapp = 'https://wa.me/923014499863?text=Hello';
  final String email = 'mailto:abdulmateenshaheen808@gmail.com';

  Future<void> _launch(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Full background image
            Center(
              child: InteractiveViewer(
                child: Image.asset(
                  'assets/images/background.jpg',
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                ),
              ),
            ),

            // Back button
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, size: 30, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Umrah Lucky Draw Registration Image instead of Button
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: () => _launch(umrahUrl),
                child: Image.asset(
                  'assets/images/lucky_draw.jpeg', // Replace with your image
                  fit: BoxFit.contain,
                  height: 110, // Adjust height to leave empty space
                ),
              ),
            ),

            // Social + WhatsApp + Email Icons
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.tiktok, size: 30, color: Colors.black),
                    onPressed: () => _launch(tiktokUrl),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.facebook, size: 30, color: Colors.blue),
                    onPressed: () => _launch(facebookUrl),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.instagram, size: 30, color: Colors.purple),
                    onPressed: () => _launch(instagramUrl),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 30, color: Colors.green),
                    onPressed: () => _launch(whatsapp),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.solidEnvelope, size: 30, color: Colors.red),
                    onPressed: () => _launch(email),
                  ),
                ],
              ),
            ),

            // Enroll Now Button at Bottom (unchanged)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: () => _launch(enrollUrl),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: const Color.fromARGB(179, 9, 85, 19),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Enroll Now',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

