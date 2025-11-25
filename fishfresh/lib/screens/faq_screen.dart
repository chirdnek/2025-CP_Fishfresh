// ignore_for_file: unused_import, sort_child_properties_last, constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_generative_ai/google_generative_ai.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF0A0F0F);          // deep charcoal
  static const panel = Color(0xFF0E1513);       // slightly lighter
  static const card = Color(0xFF111A18);        // card background
  static const accent = Color(0xFF33D9A6);      // mint/teal accent
  static const accentDark = Color(0xFF1EAD86);  // pressed/hover accent
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB8C1C0);
  static const divider = Color(0xFF23302D);

  // chat bubbles
  static const bubbleUser = Color(0xFF1B6E5A);
  static const bubbleBot = Color(0xFF161B1A);

  // avoid .withOpacity deprecation
  static const errorBg = Color.fromRGBO(244, 67, 54, 0.15);
}

// ── Lightweight in-app knowledge base (RAG context) ──────────────────────────
class KBDoc {
  final String title;
  final String text;
  KBDoc({required this.title, required this.text});
}

class AppKB {
  final List<KBDoc> docs;
  AppKB(this.docs);

  static const _stop = {
    'the','and','with','from','that','into','this','your','about','for',
    'you','are','was','were','will','can','could','shall','should','a','an',
    'to','of','on','in','at','it','is','be','as','by','or'
  };

  // Lexical scorer with title boost + min threshold (cheap but effective).
  List<KBDoc> retrieve(String query, {int k = 3}) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !_stop.contains(t))
        .toList();
    if (terms.isEmpty) return const [];

    final scored = <(KBDoc doc, int score)>[];
    for (final d in docs) {
      final title = d.title.toLowerCase();
      final body  = d.text.toLowerCase();
      var score = 0;
      for (final t in terms) {
        if (title.contains(t)) score += 2; // title weight
        if (body.contains(t))  score += 1;
      }
      if (score >= 2) scored.add((d, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(k).map((e) => e.$1).toList();
  }

  void addAll(List<KBDoc> items) => docs.addAll(items);
}

// Parse "### Title\nBody…" sections; if no headings, make one doc.
List<KBDoc> _parseKBDocs(String raw) {
  final out = <KBDoc>[];
  final hasHeadings = RegExp(r'^###\s+', multiLine: true).hasMatch(raw);
  if (!hasHeadings) {
    final t = raw.trim();
    if (t.isNotEmpty) out.add(KBDoc(title: 'FishFresh Guide', text: t));
    return out;
  }
  final parts = raw.split(RegExp(r'(?=^###\s+)'));
  for (final p in parts) {
    final lines = p.trim().split('\n');
    if (lines.isEmpty) continue;
    final first = lines.first.trim();
    if (!first.startsWith('###')) continue;
    final title = first.replaceFirst('###', '').trim();
    final body = lines.skip(1).join('\n').trim();
    if (title.isNotEmpty && body.isNotEmpty) {
      out.add(KBDoc(title: title, text: body));
    }
  }
  return out;
}

Future<void> loadKBFromAsset(String assetPath) async {
  try {
    final raw = await rootBundle.loadString(assetPath, cache: true);
    final docs = _parseKBDocs(raw);
    _kb.addAll(docs);
    debugPrint('Loaded ${docs.length} KB sections from $assetPath');
  } catch (e) {
    debugPrint('KB load skipped ($assetPath not found?): $e');
  }
}

const String _APP_BASELINE = '''
APP: FishFresh
WHAT IT DOES: Estimates fish freshness from photos (eyes, gills, skin/shine).
CORE FLOWS: Scan (good light + steady phone), View history, Optional cloud backup.
LIMITATIONS: Accuracy varies by species/handling; internet required for cloud inference.
TONE: Friendly, concise, helpful. Prefer bullet steps for how-to.
WHEN USER SAYS HELLO: Greet and offer 3 quick help topics.
''';

final AppKB _kb = AppKB([
  KBDoc(
    title: 'What is FishFresh',
    text:
        'FishFresh uses AI to estimate fish freshness from phone photos. It looks at eyes, gills, and surface luster.',
  ),
  KBDoc(
    title: 'Scanning requirements',
    text:
        'Use good lighting, avoid glare, include the eye and gills if possible, and hold the phone steady. Internet is required for cloud inference.',
  ),
  KBDoc(
    title: 'Supported species',
    text:
        'Common market species are supported first; accuracy can vary by species, handling, and storage temperature.',
  ),
  KBDoc(
    title: 'History & privacy',
    text:
        'Scans are stored locally by default; cloud sync is optional. Review Privacy Policy in Settings for details.',
  ),
]);

bool _isGreeting(String s) {
  final q = s.trim().toLowerCase();
  return RegExp(r'^(hi|hello|hey|yo|sup|good (morning|afternoon|evening))!?$').hasMatch(q);
}

// ── Screen ───────────────────────────────────────────────────────────────────
class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});
  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final List<Map<String, String>> _faqs = [
    {
      "question": "How does FishFresh work?",
      "answer":
          "FishFresh uses AI to analyze images of fish (eyes, gills, skin) and estimate freshness."
    },
    {
      "question": "Do I need an internet connection to scan?",
      "answer":
          "Most models run in the cloud for higher accuracy, so internet is required for scanning."
    },
    {
      "question": "Can I use the app for all types of fish?",
      "answer":
          "Yes, it supports the most common market species. Accuracy may vary by species."
    },
    {
      "question": "Is FishFresh accurate?",
      "answer":
          "The model is trained with thousands of labeled images and is continuously improving."
    },
    {
      "question": "Is my scan history saved?",
      "answer":
          "History is saved locally and can be synced to your account if you enable cloud backup."
    },
    {
      "question": "Can I use FishFresh offline?",
      "answer":
          "Some features work offline, but scanning typically needs internet."
    },
  ];

  late List<bool> _isExpandedList;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  final List<String> _quickTopics = const [
    'Scanning',
    'Accuracy',
    'Offline',
    'Privacy',
    'Species'
  ];

  @override
  void initState() {
    super.initState();
    _isExpandedList = List<bool>.filled(_faqs.length, false);
    // Load your long-form FishFresh text (optional but recommended)
    loadKBFromAsset('assets/kb/fishfresh_kb.txt');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredFaqs {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _faqs;
    return _faqs
        .where((f) =>
            (f["question"]!.toLowerCase().contains(q)) ||
            (f["answer"]!.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: const [
                  Icon(Icons.help_outline, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Text(
                    'Help & FAQ',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "We’re here to help you with anything and everything on FishFresh.",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),

              // Search
              _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),

              // Quick topics
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickTopics.map((t) {
                  final selected = _query.toLowerCase() == t.toLowerCase();
                  return FilterChip(
                    label: Text(t),
                    selected: selected,
                    onSelected: (_) => setState(() => _query = t),
                    backgroundColor: AppColors.card,
                    selectedColor: AppColors.accentDark,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                    side: const BorderSide(color: AppColors.divider),
                    showCheckmark: false,
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),
              const _SectionTitle('FAQ'),

              const SizedBox(height: 8),
              ...List.generate(_filteredFaqs.length, (index) {
                final item = _filteredFaqs[index];
                final originalIndex = _faqs.indexOf(item);
                final expanded = (_isExpandedList.length > originalIndex) &&
                    _isExpandedList[originalIndex];

                return _FaqCard(
                  question: item["question"]!,
                  answer: item["answer"]!,
                  expanded: expanded,
                  onChanged: (e) {
                    setState(() {
                      if (_isExpandedList.length == _faqs.length) {
                        _isExpandedList[originalIndex] = e;
                      }
                    });
                  },
                );
              }),

              const SizedBox(height: 24),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 16),

              // CTA
              const Text(
                "Still stuck? Our assistant can help:",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.forum),
                  label: const Text('Ask FishFresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _MiniChatSheet(),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.article_outlined, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search help',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({
    required this.question,
    required this.answer,
    required this.expanded,
    required this.onChanged,
  });

  final String question;
  final String answer;
  final bool expanded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? AppColors.accent : AppColors.divider,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          iconColor: AppColors.accent,
          collapsedIconColor: AppColors.textSecondary,
          trailing: Icon(expanded ? Icons.remove : Icons.add),
          title: Text(
            question,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Text(
              answer,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ],
          onExpansionChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Chat Sheet ────────────────────────────────────────────────────────────────
class _MiniChatSheet extends StatefulWidget {
  const _MiniChatSheet();
  @override
  State<_MiniChatSheet> createState() => _MiniChatSheetState();
}

class ChatMessage {
  final bool fromUser;
  final String text;
  ChatMessage({required this.fromUser, required this.text});
}

class _MiniChatSheetState extends State<_MiniChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];

  GenerativeModel? _model; // set in initState
  bool _busy = false;
  String? _error;

  final _quickReplies = const [
    'How do I take a good scan?',
    'Which species are supported?',
    'Why do I need internet?',
    'How accurate is it?',
    'How is data stored?'
  ];

  @override
  void initState() {
    super.initState();
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      _error =
          'Gemini API key is not configured. Launch with --dart-define=GEMINI_API_KEY=YOUR_KEY';
    } else {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.2,
          topP: 0.9,
          topK: 32,
          maxOutputTokens: 256,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendQuick(String q) async {
    _controller.text = q;
    await _send();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(ChatMessage(fromUser: true, text: text));
      _busy = true;
    });
    _controller.clear();

    try {
      // Greeting fast-path (no API)
      if (_isGreeting(text)) {
        final reply = "Hi! I’m the FishFresh assistant 👋\n"
            "I can help with:\n"
            "• How to take a good scan\n"
            "• Accuracy & supported species\n"
            "• Offline use and privacy";
        setState(() => _messages.add(ChatMessage(fromUser: false, text: reply)));
        return;
      }

      if (_model == null) throw Exception(_error ?? 'Model not available');

      // Retrieve KB
      final top = _kb.retrieve(text, k: 3);
      final kbContext =
          top.isEmpty ? 'None' : top.map((d) => '### ${d.title}\n${d.text}').join('\n\n');

      final system = '''
ROLE: You are the in-app assistant for FishFresh.
BASELINE:
$_APP_BASELINE

KNOWLEDGE (optional):
$kbContext

INSTRUCTIONS:
- Prefer the KNOWLEDGE when relevant; otherwise answer using the BASELINE.
- If the user is vague, ask one short clarifying question.
- Be concise, use bullets for steps.
''';

      // Stream the response so it "types"
      final stream = _model!.generateContentStream([
        Content.text(system),
        Content.text('User: $text'),
      ]);

      // placeholder bot message
      setState(() => _messages.add(ChatMessage(fromUser: false, text: '')));
      final idx = _messages.length - 1;

      final buffer = StringBuffer();
      await for (final chunk in stream) {
        final piece = chunk.text ?? '';
        if (piece.isEmpty) continue;
        buffer.write(piece);
        setState(() => _messages[idx] = ChatMessage(fromUser: false, text: buffer.toString()));
        _jumpToBottom();
      }
    } catch (e) {
      setState(() => _messages.add(ChatMessage(fromUser: false, text: 'Error: $e')));
    } finally {
      setState(() => _busy = false);
      _jumpToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Grab handle
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Header
              const SizedBox(height: 12),
              const Text(
                "Ask FishFresh",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                "Smart help grounded on your FAQ",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Divider(color: AppColors.divider, height: 1),

              // Error banner if key missing
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),

              // Messages
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final align = m.fromUser ? Alignment.centerRight : Alignment.centerLeft;
                    final bg = m.fromUser ? AppColors.bubbleUser : AppColors.bubbleBot;
                    final txtColor = Colors.white;

                    return Align(
                      alignment: align,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.82,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: m.fromUser ? AppColors.accent : AppColors.divider,
                          ),
                        ),
                        child: Text(m.text, style: TextStyle(color: txtColor, height: 1.4)),
                      ),
                    );
                  },
                ),
              ),

              // Quick replies
              if (_error == null)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (_, i) {
                      final t = _quickReplies[i];
                      return ActionChip(
                        label: Text(t, style: const TextStyle(color: Colors.black)),
                        backgroundColor: AppColors.accent,
                        onPressed: _busy ? null : () => _sendQuick(t),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _quickReplies.length,
                  ),
                ),

              // Composer
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: "Type your question…",
                          hintStyle: const TextStyle(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.accent),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onSubmitted: (_) => _busy ? null : _send(),
                        enabled: _error == null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (_busy || _error != null) ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
