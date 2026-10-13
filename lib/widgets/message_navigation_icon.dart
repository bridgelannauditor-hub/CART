import 'package:flutter/material.dart';

import '../repositories/message_repository.dart';
import '../services/session_service.dart';

class MessageNavigationIcon extends StatefulWidget {
  final bool selected;
  const MessageNavigationIcon({super.key, this.selected = false});
  @override
  State<MessageNavigationIcon> createState() => _MessageNavigationIconState();
}

class _MessageNavigationIconState extends State<MessageNavigationIcon> {
  late final Stream<int>? _unreadCount;
  @override
  void initState() {
    super.initState();
    final userId = SessionService.userId;
    _unreadCount = userId == null
        ? null
        : MessageRepository().watchUnreadCount(userId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadCount,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(
            widget.selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
          ),
        );
      },
    );
  }
}
