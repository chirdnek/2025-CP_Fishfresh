import 'package:flutter/material.dart';

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _FAQScreenState createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  List<Map<String, String>> faqs = [
    {"question": "How does FishFresh work?", "answer": "FishFresh uses AI to analyze images of fish and determine freshness."},
    {"question": "Do I need an internet connection to scan?", "answer": "Yes, scanning requires an internet connection to process the image."},
    {"question": "Can I use the app for all types of fish?", "answer": "Yes, the app supports most commonly consumed fish types."},
    {"question": "Is FishFresh accurate?", "answer": "Yes, it's trained with thousands of fish images to ensure high accuracy."},
    {"question": "Is my scan history saved?", "answer": "Your scan history is saved locally and optionally on the cloud."},
    {"question": "Can I use FishFresh offline?", "answer": "Limited functionality is available offline, but scanning requires internet."},
  ];

  List<bool> _isExpandedList = [];

  @override
  void initState() {
    super.initState();
    _isExpandedList = List.filled(faqs.length, false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.help_outline, color: Colors.white70),
              SizedBox(height: 10),
              Text(
                "We’re here to help you with\nanything and everything on\nFish Fresh",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "FishFresh is a mobile application that helps users check the freshness of fish using AI-powered image analysis...",
                style: TextStyle(color: Colors.white60),
              ),
              SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Search Help',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(50),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 30),
              Text("FAQ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Divider(color: Colors.white38),
              ...List.generate(faqs.length, (index) {
                return ExpansionTile(
                  collapsedIconColor: Colors.white,
                  iconColor: Colors.white,
                  tilePadding: EdgeInsets.symmetric(horizontal: 0),
                  title: Text(
                    faqs[index]["question"]!,
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: Icon(
                    _isExpandedList[index] ? Icons.remove : Icons.add,
                    color: Colors.white,
                  ),
                  children: [
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        faqs[index]["answer"]!,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _isExpandedList[index] = expanded;
                    });
                  },
                );
              }),
              Divider(color: Colors.white38),
              SizedBox(height: 20),
              Text("Still stuck? Help us a mail away", style: TextStyle(color: Colors.white70)),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  // Add your send message logic here
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4AD9A0), // Green color
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: Text("Send a message", style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
