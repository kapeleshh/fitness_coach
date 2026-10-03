import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/health_api_service.dart';
import '../theme/app_theme.dart';

/// Chat with the coach. Replies stream in from POST /api/coach/chat. The
/// backend grounds every answer in the synced data, so the app sends only
/// the question, and each question is answered on its own.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, this.service});

  /// Defaults to the app-wide [healthApiService]; injectable for tests.
  final HealthApiService? service;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _ChatMessage {
  _ChatMessage.user(this.text) : fromUser = true;
  _ChatMessage.coach()
      : fromUser = false,
        text = '';

  final bool fromUser;
  String text;
  bool isError = false;
}

class _CoachScreenState extends State<CoachScreen> {
  static const _suggestions = [
    'How recovered am I today?',
    'Should I train hard today?',
    'How has my training load changed this week?',
  ];

  final _messages = <_ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<String>? _reply;

  HealthApiService get _service => widget.service ?? healthApiService;
  bool get _waiting => _reply != null;

  @override
  void dispose() {
    _reply?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask(String raw) {
    final question = raw.trim();
    if (question.isEmpty || _waiting) return;
    final reply = _ChatMessage.coach();
    setState(() {
      _messages
        ..add(_ChatMessage.user(question))
        ..add(reply);
      _input.clear();
      _reply = _service.askCoach(question).listen(
        (chunk) {
          setState(() => reply.text += chunk);
          _scrollToEnd();
        },
        onError: (Object e) => _finish(reply, error: e),
        onDone: () => _finish(reply),
        cancelOnError: true,
      );
    });
    _scrollToEnd();
  }

  void _finish(_ChatMessage reply, {Object? error}) {
    if (!mounted) return;
    setState(() {
      _reply = null;
      if (error != null) {
        reply.isError = true;
        reply.text = error is ApiException
            ? error.message
            : "Couldn't reach the coach at $apiBaseUrl. "
                'Make sure the backend server is running.';
      } else if (reply.text.trim().isEmpty) {
        reply.isError = true;
        reply.text = 'The coach returned an empty reply. Try asking again.';
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Coach'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildIntro()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _Bubble(message: _messages[i]),
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.forum_rounded, size: 56, color: AppTheme.primaryColor),
        const SizedBox(height: 16),
        const Text(
          'Ask about your recovery, sleep or training.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Answers use only numbers from your synced Garmin data: readiness, "
          "wellness and training load. Activities recorded only on Strava "
          "aren't shared with the coach.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: () => _ask(s)),
          ],
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return Container(
      color: AppTheme.surfaceColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'Ask your coach…',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send_rounded),
                    color: AppTheme.primaryColor,
                    onPressed: _waiting ? null : () => _ask(_input.text),
                  ),
                ],
              ),
              const Text(
                "Each question is answered fresh from your latest data; the "
                "coach doesn't see earlier messages.",
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    final pending = !fromUser && message.text.isEmpty && !message.isError;
    final Color background = fromUser
        ? AppTheme.primaryColor
        : message.isError
            ? AppTheme.errorColor.withValues(alpha: 0.08)
            : AppTheme.cardColor;
    final Color foreground = fromUser
        ? Colors.white
        : message.isError
            ? AppTheme.errorColor
            : AppTheme.textPrimary;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            boxShadow: fromUser
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Text(
            pending ? 'Thinking…' : message.text,
            style: TextStyle(
              color: pending ? AppTheme.textTertiary : foreground,
              fontStyle: pending ? FontStyle.italic : FontStyle.normal,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
