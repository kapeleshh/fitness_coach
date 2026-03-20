import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ask Coach Screen - AI Chat Interface
class AskCoachScreen extends StatefulWidget {
  const AskCoachScreen({super.key});

  @override
  State<AskCoachScreen> createState() => _AskCoachScreenState();
}

class _AskCoachScreenState extends State<AskCoachScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Add initial greeting
    _messages.add(_ChatMessage(
      text: "Hi! 👋 I'm your AI health coach. Ask me anything about your health data, patterns, or for personalized recommendations.\n\nTry questions like:\n• \"Why was my sleep bad last night?\"\n• \"When should I run tomorrow?\"\n• \"What affects my stress?\"\n• \"Am I overtraining?\"",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _messageController.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    // Simulate AI response
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(
            text: _generateResponse(text),
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    });
  }

  String _generateResponse(String question) {
    final q = question.toLowerCase();

    if (q.contains('sleep') && (q.contains('bad') || q.contains('poor') || q.contains('why'))) {
      return "Looking at your data from yesterday:\n\n"
          "Your sleep score was 58 (vs your average of 76). Here's what I found:\n\n"
          "1. 🏃 You exercised at 9:30 PM (your data shows -23% sleep quality for late workouts)\n\n"
          "2. 😰 Higher than usual stress at bedtime (stress score: 45)\n\n"
          "3. ⏰ Later bedtime (11:45 PM vs your optimal 10:30 PM)\n\n"
          "💡 Suggestion: Tomorrow, try finishing your workout by 7 PM and going to bed 30 minutes earlier.";
    }

    if (q.contains('run') || q.contains('workout') || q.contains('exercise') || q.contains('train')) {
      if (q.contains('tomorrow') || q.contains('when') || q.contains('best time')) {
        return "Based on your patterns, your Body Battery peaks around 10-11 AM tomorrow.\n\n"
            "🏃 Best workout window: 9:30 AM - 11:30 AM\n\n"
            "Your predicted energy at that time: 78\n\n"
            "I recommend:\n"
            "• If you want an intense session: Go for it in this window!\n"
            "• If you feel tired: A moderate 30-min run would be perfect\n\n"
            "Should I set a reminder for you?";
      }
      return "Looking at your training data:\n\n"
          "📊 Your current training status: Productive\n"
          "⏰ Recovery time remaining: 12 hours\n"
          "💪 Body Battery: 72\n\n"
          "You're in good shape for a workout today! Your HRV is stable and you've had decent sleep.\n\n"
          "Based on your patterns, morning workouts (before 10 AM) tend to give you 20% better performance.";
    }

    if (q.contains('stress') || q.contains('anxious') || q.contains('worried')) {
      return "I've analyzed your stress patterns:\n\n"
          "📈 Your stress tends to spike:\n"
          "• Tuesday 2-3 PM (likely team meetings) - 45% higher\n"
          "• Sunday evenings (pre-week anxiety?) - 30% higher\n\n"
          "What helps reduce your stress:\n"
          "✅ Morning exercise: -25% stress\n"
          "✅ Good sleep (>75 score): -35% stress\n"
          "✅ 8,000+ steps: -15% stress\n\n"
          "💡 Try a 5-minute breathing exercise before your Tuesday meeting. Want me to remind you?";
    }

    if (q.contains('overtrain') || q.contains('recovery') || q.contains('rest')) {
      return "Let me check your recovery indicators:\n\n"
          "🟢 HRV Trend: Stable (+2% this week)\n"
          "🟢 Resting HR: Normal (52 BPM, your baseline is 51)\n"
          "🟢 Sleep Quality: Good (avg 74 this week)\n"
          "🟡 Training Load: Slightly elevated\n\n"
          "Overall: You're NOT overtraining! Your body is handling the load well.\n\n"
          "However, I noticed you've had 4 workouts in 5 days. Consider taking tomorrow as a rest day to maintain your good recovery status.";
    }

    if (q.contains('tired') || q.contains('energy') || q.contains('fatigue')) {
      return "I looked into why you might be feeling low energy:\n\n"
          "Possible factors from your recent data:\n\n"
          "1. 😴 Sleep: Your deep sleep has been 15% below average this week\n\n"
          "2. 🏋️ Training: You've had 3 intense workouts in the last 4 days\n\n"
          "3. 😰 Stress: Yesterday's average stress was higher than usual (42 vs 35)\n\n"
          "💡 Recommendations:\n"
          "• Tonight: Try going to bed 30 min earlier\n"
          "• Tomorrow: Light activity only (walk or yoga)\n"
          "• This week: Aim for 8,000 steps but skip intense training";
    }

    // Default response
    return "That's a great question! Based on your health data:\n\n"
        "📊 Your current status:\n"
        "• Health Score: 72 (Good)\n"
        "• Body Battery: 68\n"
        "• Sleep Score: 74\n"
        "• Stress: Low\n\n"
        "Is there something specific you'd like me to analyze? I can look into:\n"
        "• Sleep patterns and quality\n"
        "• Stress triggers and management\n"
        "• Training optimization\n"
        "• Recovery recommendations\n\n"
        "Just ask me anything!";
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    color: AppTheme.primaryColor,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Coach',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Ask anything about your health',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Quick Questions
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _QuickQuestionChip(
                    label: 'Why am I tired?',
                    onTap: () {
                      _messageController.text = 'Why am I tired?';
                      _sendMessage();
                    },
                  ),
                  _QuickQuestionChip(
                    label: 'Best run time?',
                    onTap: () {
                      _messageController.text = 'When should I run tomorrow?';
                      _sendMessage();
                    },
                  ),
                  _QuickQuestionChip(
                    label: 'Sleep tips',
                    onTap: () {
                      _messageController.text = 'Why was my sleep bad?';
                      _sendMessage();
                    },
                  ),
                  _QuickQuestionChip(
                    label: 'Stress patterns',
                    onTap: () {
                      _messageController.text = 'What affects my stress?';
                      _sendMessage();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _TypingIndicator();
                  }
                  return _ChatBubble(message: _messages[index]);
                },
              ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Ask your AI coach...',
                        hintStyle: const TextStyle(color: AppTheme.textTertiary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.backgroundColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: message.isUser ? AppTheme.primaryColor : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  color: message.isUser ? Colors.white : AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (message.isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TypingDot(delay: 0),
                SizedBox(width: 4),
                _TypingDot(delay: 200),
                SizedBox(width: 4),
                _TypingDot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.3 + _controller.value * 0.7),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _QuickQuestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickQuestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(0.3),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
