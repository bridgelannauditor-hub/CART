import 'package:flutter/material.dart';

import '../repositories/message_repository.dart';
import 'count_badge.dart';
import '../services/session_service.dart';

class MessageNavigationIcon extends StatefulWidget {
  final bool selected;
  const MessageNavigationIcon({super.key, this.selected = false});
  @override
  State<MessageNavigationIcon> createState() => _MessageNavigationIconState();
}

class _MessageNavigationIconState extends State<MessageNavigationIcon> {
  late final Stream<int>? _unreadCount;
  int _initial = 0;
  @override
  void initState() {
    super.initState();
    final userId = SessionService.userId;
    final repository = MessageRepository();
    _unreadCount = userId == null ? null : repository.watchUnreadCount(userId);
    // Show the count right away instead of waiting for the live feed.
    if (userId != null) {
      repository.getUnreadCount(userId).then((count) {
        if (mounted) setState(() => _initial = count);
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadCount,
      initialData: _initial,
      builder: (context, snapshot) {
        final count = snapshot.data ?? _initial;
        return CountBadge(
          count: count,
          child: Icon(
            widget.selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
          ),
        );
      },
    );
  }
}
