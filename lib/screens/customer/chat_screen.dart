import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../constants/app_colors.dart';
import '../../models/message_model.dart';
import '../../repositories/message_repository.dart';
import '../../repositories/product_repository.dart';
import '../../services/session_service.dart';
import '../../services/cloudinary_service.dart';
import '../../widgets/product_image.dart';
import 'product_details_screen.dart';
import 'shop_screen.dart';

class ChatScreen extends StatefulWidget {
  final int otherUserId;
  final String otherUserName;
  final String? contextType;
  final int? contextId;
  final String? contextName;
  final String? contextImage;
  final double? contextPrice;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.contextType,
    this.contextId,
    this.contextName,
    this.contextImage,
    this.contextPrice,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessageRepository _messageRepository = MessageRepository();
  final ProductRepository _productRepository = ProductRepository();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocus = FocusNode();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<MessageModel>>? _messageSubscription;
  Timer? _recordingTimer;

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false;
  bool _showEmojiPicker = false;
  Duration _recordingDuration = Duration.zero;
  DateTime? _recordingStartedAt;
  String? _pendingVoicePath;
  Duration _pendingVoiceDuration = Duration.zero;
  MessageModel? _replyingTo;
  late bool _attachContextToNextMessage;

  int? get _currentUserId => SessionService.userId;

  @override
  void initState() {
    super.initState();
    _attachContextToNextMessage = widget.contextType != null;
    _textController.addListener(_onComposerChanged);
    _startListening();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _messageFocus.dispose();
    _recordingTimer?.cancel();
    unawaited(_recorder.dispose());
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _onComposerChanged() {
    if (mounted) setState(() {});
  }

  void _startListening() {
    final userId = _currentUserId;
    if (userId == null) return;

    _messageSubscription = _messageRepository
        .watchConversation(userId, widget.otherUserId)
        .listen(
          (messages) {
            if (!mounted) return;
            setState(() {
              _messages = messages;
              _isLoading = false;
            });
            _scrollToBottom();

            final hasUnread = messages.any(
              (message) => message.receiverId == userId && message.isRead == 0,
            );
            if (hasUnread) {
              unawaited(
                _messageRepository.markConversationRead(
                  currentUserId: userId,
                  otherUserId: widget.otherUserId,
                ),
              );
            }
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not load this conversation.'),
              ),
            );
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send([String? replacementText]) async {
    final text = (replacementText ?? _textController.text).trim();
    final userId = _currentUserId;
    if (text.isEmpty || userId == null || _isSending) return;

    setState(() => _isSending = true);
    if (replacementText == null) _textController.clear();

    try {
      await _messageRepository.sendMessage(
        senderId: userId,
        receiverId: widget.otherUserId,
        text: text,
        contextType: _attachContextToNextMessage ? widget.contextType : null,
        contextId: _attachContextToNextMessage ? widget.contextId : null,
        contextName: _attachContextToNextMessage ? widget.contextName : null,
        contextImage: _attachContextToNextMessage ? widget.contextImage : null,
        contextPrice: _attachContextToNextMessage ? widget.contextPrice : null,
        replyToId: _replyingTo?.documentId,
        replyText: _replyingTo?.previewText,
        replyType: _replyingTo?.messageType,
      );
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _attachContextToNextMessage = false;
        _replyingTo = null;
      });
    } catch (_) {
      if (!mounted) return;
      _textController.text = text;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent.')),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _sendMedia(
    String path, {
    required String type,
    int? durationMs,
  }) async {
    final userId = _currentUserId;
    if (userId == null || _isSending) return false;
    setState(() => _isSending = true);
    try {
      final url = await CloudinaryService.upload(
        File(path),
        resourceType: type == 'image' ? 'image' : 'video',
      );
      await _messageRepository.sendMessage(
        senderId: userId,
        receiverId: widget.otherUserId,
        text: '',
        messageType: type,
        mediaUrl: url,
        mediaDurationMs: durationMs,
        contextType: _attachContextToNextMessage ? widget.contextType : null,
        contextId: _attachContextToNextMessage ? widget.contextId : null,
        contextName: _attachContextToNextMessage ? widget.contextName : null,
        contextImage: _attachContextToNextMessage ? widget.contextImage : null,
        contextPrice: _attachContextToNextMessage ? widget.contextPrice : null,
        replyToId: _replyingTo?.documentId,
        replyText: _replyingTo?.previewText,
        replyType: _replyingTo?.messageType,
      );
      if (!mounted) return false;
      setState(() {
        _isSending = false;
        _attachContextToNextMessage = false;
        _replyingTo = null;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _isSending = false);
      _showError('The attachment could not be sent. Please try again.');
      return false;
    }
  }

  Future<void> _takePhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo != null) await _sendMedia(photo.path, type: 'image');
  }

  Future<void> _openGallery() async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Choose a video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final picker = ImagePicker();
    final media = choice == 'image'
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await picker.pickVideo(source: ImageSource.gallery);
    if (media != null) await _sendMedia(media.path, type: choice);
  }

  Future<void> _toggleRecording() async {
    if (_isSending) return;
    if (_isRecording) {
      _recordingTimer?.cancel();
      final path = await _recorder.stop();
      final duration = _recordingStartedAt == null
          ? _recordingDuration
          : DateTime.now().difference(_recordingStartedAt!);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _recordingStartedAt = null;
      });
      if (path != null && duration.inMilliseconds >= 500) {
        setState(() {
          _pendingVoicePath = path;
          _pendingVoiceDuration = duration;
        });
      }
      return;
    }

    if (_pendingVoicePath != null) {
      _showError('Send or discard the voice preview first.');
      return;
    }

    if (!await _recorder.hasPermission()) {
      _showError('Microphone permission is needed to record a voice message.');
      return;
    }
    final temp = await getTemporaryDirectory();
    final path =
        '${temp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    _recordingStartedAt = DateTime.now();
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _recordingStartedAt == null) return;
      setState(() {
        _recordingDuration = DateTime.now().difference(_recordingStartedAt!);
      });
    });
  }

  void _toggleEmojiPicker() {
    FocusScope.of(context).unfocus();
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final selection = _textController.selection;
    final start = selection.isValid
        ? selection.start
        : _textController.text.length;
    final end = selection.isValid ? selection.end : start;
    final updated = _textController.text.replaceRange(start, end, emoji);
    _textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _sendPendingVoice() async {
    final path = _pendingVoicePath;
    if (path == null) return;
    final duration = _pendingVoiceDuration;
    final sent = await _sendMedia(
      path,
      type: 'audio',
      durationMs: duration.inMilliseconds,
    );
    if (!mounted || !sent) return;
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceDuration = Duration.zero;
    });
    unawaited(File(path).delete().then<void>((_) {}).catchError((_) {}));
  }

  void _discardPendingVoice() {
    final path = _pendingVoicePath;
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceDuration = Duration.zero;
    });
    if (path != null) {
      unawaited(File(path).delete().then<void>((_) {}).catchError((_) {}));
    }
  }

  Future<void> _showMessageActions(MessageModel message, bool isMine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            if (message.messageText.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy message'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            if (isMine &&
                message.messageType == 'text' &&
                message.messageText.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit message'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (isMine && message.documentId != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete message'),
                textColor: AppColors.error,
                iconColor: AppColors.error,
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replyingTo = message);
        _messageFocus.requestFocus();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.messageText));
        _showError('Message copied.');
      case 'edit':
        await _editMessage(message);
      case 'delete':
        await _deleteMessage(message);
    }
  }

  Future<void> _editMessage(MessageModel message) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (context) =>
          _EditMessageDialog(initialText: message.messageText),
    );
    if (updated == null || updated.isEmpty || updated == message.messageText) {
      return;
    }
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await _messageRepository.editMessage(
        userA: userId,
        userB: widget.otherUserId,
        message: message,
        text: updated,
      );
    } catch (_) {
      _showError('The message could not be edited.');
    }
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final messageId = message.documentId;
    final userId = _currentUserId;
    if (messageId == null || userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for both people.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _messageRepository.deleteMessage(
        userA: userId,
        userB: widget.otherUserId,
        messageId: messageId,
      );
    } catch (_) {
      _showError('The message could not be deleted.');
    }
  }

  Future<void> _viewContext(String type, int? id) async {
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'product'
                ? 'This product is no longer available.'
                : 'This shop is no longer available.',
          ),
        ),
      );
      return;
    }

    if (type == 'shop') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ShopScreen(sellerId: id)),
      );
      return;
    }

    try {
      final product = await _productRepository.getProductById(id);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This product is no longer available.')),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailsScreen(product: product),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this product.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _currentUserId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.otherUserName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _messages.isEmpty
                  ? _EmptyChatState(name: widget.otherUserName)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMine = message.senderId == userId;
                        return _MessageBubble(
                          message: message,
                          isMine: isMine,
                          onViewContext: _viewContext,
                          onLongPress: () =>
                              _showMessageActions(message, isMine),
                        );
                      },
                    ),
            ),
            if (_attachContextToNextMessage && widget.contextType != null)
              _PendingMessageContext(
                type: widget.contextType!,
                name: widget.contextName ?? '',
                image: widget.contextImage,
                price: widget.contextPrice,
                onView: () =>
                    _viewContext(widget.contextType!, widget.contextId),
                onRemove: () {
                  setState(() => _attachContextToNextMessage = false);
                },
              ),
            if (_replyingTo != null)
              _PendingReply(
                message: _replyingTo!,
                onRemove: () => setState(() => _replyingTo = null),
              ),
            if (_pendingVoicePath != null)
              _PendingVoiceMessage(
                path: _pendingVoicePath!,
                duration: _pendingVoiceDuration,
                isSending: _isSending,
                onDiscard: _discardPendingVoice,
                onSend: _sendPendingVoice,
              ),
            _ChatInputBar(
              controller: _textController,
              focusNode: _messageFocus,
              isSending: _isSending,
              isRecording: _isRecording,
              recordingDuration: _recordingDuration,
              onCamera: _takePhoto,
              onGallery: _openGallery,
              onRecord: _toggleRecording,
              onEmoji: _toggleEmojiPicker,
              onSend: () => _send(),
              onLike: () => _send('👍'),
            ),
            if (_showEmojiPicker) _EmojiPicker(onSelected: _insertEmoji),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Future<void> Function(String type, int? id) onViewContext;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onViewContext,
    required this.onLongPress,
  });

  String get _formattedTime {
    final date = DateTime.tryParse(message.messageDate)?.toLocal();
    if (date == null) return '';

    final hour24 = date.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';

    return "$hour12:$minute $period";
  }

  String get _statusLabel {
    if (message.isRead == 1) return "Seen";
    return "Delivered";
  }

  @override
  Widget build(BuildContext context) {
    final firstName = SessionService.firstName;
    final initial = (isMine && firstName != null && firstName.isNotEmpty)
        ? firstName[0].toUpperCase()
        : "?";

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.62,
      ),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        message.messageText,
        style: TextStyle(
          color: isMine ? Colors.white : AppColors.textPrimary,
          fontSize: 14,
        ),
      ),
    );

    final meta = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formattedTime,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 4),
            Text(
              "•",
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: message.isRead == 1
                    ? AppColors.secondary
                    : AppColors.textSecondary,
              ),
            ),
          ],
          if (message.editedAt != null) ...[
            const SizedBox(width: 4),
            const Text(
              '• Edited',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.replyText != null) ...[
          _ReplyQuote(
            text: message.replyText!,
            type: message.replyType ?? 'text',
            isMine: isMine,
          ),
          const SizedBox(height: 5),
        ],
        if (message.contextType != null) ...[
          _MessageContextCard(
            type: message.contextType!,
            name: message.contextName ?? '',
            image: message.contextImage,
            price: message.contextPrice,
            onView: () =>
                onViewContext(message.contextType!, message.contextId),
          ),
          const SizedBox(height: 5),
        ],
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
          _MessageMedia(message: message, isMine: isMine),
          if (message.messageText.isNotEmpty) const SizedBox(height: 5),
        ],
        if (message.messageText.isNotEmpty) bubble,
        const SizedBox(height: 3),
        meta,
      ],
    );

    final avatar = CircleAvatar(
      radius: 14,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: isMine
                ? [Flexible(child: content), const SizedBox(width: 6), avatar]
                : [Flexible(child: content)],
          ),
        ),
      ),
    );
  }
}

class _EditMessageDialog extends StatefulWidget {
  final String initialText;

  const _EditMessageDialog({required this.initialText});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(hintText: 'Message'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PendingReply extends StatelessWidget {
  final MessageModel message;
  final VoidCallback onRemove;

  const _PendingReply({required this.message, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(width: 3, height: 38, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Replying to message',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  final String text;
  final String type;
  final bool isMine;

  const _ReplyQuote({
    required this.text,
    required this.type,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMine
            ? AppColors.primary.withValues(alpha: .12)
            : AppColors.lightGrey.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Text(
        text.isEmpty
            ? switch (type) {
                'image' => 'Photo',
                'video' => 'Video',
                'audio' => 'Voice message',
                _ => 'Message',
              }
            : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _PendingVoiceMessage extends StatefulWidget {
  final String path;
  final Duration duration;
  final bool isSending;
  final VoidCallback onDiscard;
  final VoidCallback onSend;

  const _PendingVoiceMessage({
    required this.path,
    required this.duration,
    required this.isSending,
    required this.onDiscard,
    required this.onSend,
  });

  @override
  State<_PendingVoiceMessage> createState() => _PendingVoiceMessageState();
}

class _PendingVoiceMessageState extends State<_PendingVoiceMessage> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  StreamSubscription<PlayerState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  String get _durationLabel {
    final minutes = widget.duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (widget.duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: _state == PlayerState.playing
                ? 'Pause preview'
                : 'Play preview',
            onPressed: widget.isSending
                ? null
                : () async {
                    if (_state == PlayerState.playing) {
                      await _player.pause();
                    } else {
                      await _player.play(DeviceFileSource(widget.path));
                    }
                  },
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: AppColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review voice message',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _durationLabel,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Discard recording',
            onPressed: widget.isSending
                ? null
                : () async {
                    await _player.stop();
                    widget.onDiscard();
                  },
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
          ),
          IconButton.filled(
            tooltip: 'Send voice message',
            onPressed: widget.isSending
                ? null
                : () async {
                    await _player.stop();
                    widget.onSend();
                  },
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _MessageMedia extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const _MessageMedia({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl!;
    switch (message.messageType) {
      case 'video':
        return _VideoMessage(url: url);
      case 'audio':
        return _AudioMessage(
          url: url,
          durationMs: message.mediaDurationMs,
          isMine: isMine,
        );
      default:
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.transparent,
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 230,
              height: 190,
              child: ProductImage(
                path: url,
                fit: BoxFit.cover,
                placeholder: const ColoredBox(
                  color: AppColors.lightGrey,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        );
    }
  }
}

class _VideoMessage extends StatefulWidget {
  final String url;

  const _VideoMessage({required this.url});

  @override
  State<_VideoMessage> createState() => _VideoMessageState();
}

class _VideoMessageState extends State<_VideoMessage> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted && _controller.value.isInitialized) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 230,
        height: 190,
        color: Colors.black,
        child: _failed
            ? const Center(
                child: Icon(Icons.videocam_off_outlined, color: Colors.white70),
              )
            : !_controller.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  Center(
                    child: IconButton.filled(
                      onPressed: () {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      },
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AudioMessage extends StatefulWidget {
  final String url;
  final int? durationMs;
  final bool isMine;

  const _AudioMessage({
    required this.url,
    required this.durationMs,
    required this.isMine,
  });

  @override
  State<_AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<_AudioMessage> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs ?? 0);
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSubscription = _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _stateSubscription = _player.onPlayerStateChanged.listen((value) {
      if (mounted) setState(() => _state = value);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isMine ? Colors.white : AppColors.primary;
    final totalMs = _duration.inMilliseconds <= 0
        ? 1
        : _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, totalMs);
    return Container(
      width: 235,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: widget.isMine ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              if (_state == PlayerState.playing) {
                await _player.pause();
              } else {
                await _player.play(UrlSource(widget.url));
              }
            },
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: foreground,
            ),
          ),
          Expanded(
            child: Slider(
              value: positionMs.toDouble(),
              max: totalMs.toDouble(),
              activeColor: foreground,
              inactiveColor: foreground.withValues(alpha: .3),
              onChanged: (value) =>
                  _player.seek(Duration(milliseconds: value.round())),
            ),
          ),
          Text(
            _time(_position == Duration.zero ? _duration : _position),
            style: TextStyle(fontSize: 10, color: foreground),
          ),
        ],
      ),
    );
  }
}

class _PendingMessageContext extends StatelessWidget {
  final String type;
  final String name;
  final String? image;
  final double? price;
  final VoidCallback onView;
  final VoidCallback onRemove;

  const _PendingMessageContext({
    required this.type,
    required this.name,
    this.image,
    this.price,
    required this.onView,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type == 'product'
                      ? 'Asking about this product'
                      : 'Asking about this shop',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                _MessageContextCard(
                  type: type,
                  name: name,
                  image: image,
                  price: price,
                  onView: onView,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageContextCard extends StatelessWidget {
  final String type;
  final String name;
  final String? image;
  final double? price;
  final VoidCallback onView;

  const _MessageContextCard({
    required this.type,
    required this.name,
    this.image,
    this.price,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final isProduct = type == 'product';

    return Container(
      width: 245,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: (image ?? '').isNotEmpty
                      ? ProductImage(
                          path: image!,
                          fit: BoxFit.cover,
                          placeholder: _contextFallback(isProduct),
                        )
                      : _contextFallback(isProduct),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProduct ? 'Product' : 'Shop',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.isEmpty ? (isProduct ? 'Product' : 'Shop') : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isProduct && price != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '₱${price!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isProduct ? 'View Product' : 'View Shop',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextFallback(bool isProduct) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Icon(
        isProduct ? Icons.inventory_2_outlined : Icons.storefront_outlined,
        color: AppColors.primary,
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool isRecording;
  final Duration recordingDuration;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRecord;
  final VoidCallback onEmoji;
  final VoidCallback onSend;
  final VoidCallback onLike;

  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.isRecording,
    required this.recordingDuration,
    required this.onCamera,
    required this.onGallery,
    required this.onRecord,
    required this.onEmoji,
    required this.onSend,
    required this.onLike,
  });

  String get _recordingLabel {
    final minutes = recordingDuration.inMinutes.toString().padLeft(2, '0');
    final seconds = (recordingDuration.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          _ComposerIcon(
            icon: Icons.camera_alt_rounded,
            tooltip: 'Take photo',
            onTap: isSending ? null : onCamera,
          ),
          _ComposerIcon(
            icon: Icons.photo_rounded,
            tooltip: 'Choose photo or video',
            onTap: isSending ? null : onGallery,
          ),
          _ComposerIcon(
            icon: isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
            tooltip: isRecording ? 'Stop recording' : 'Record voice message',
            color: isRecording ? AppColors.error : AppColors.primary,
            onTap: isSending ? null : onRecord,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: isRecording
                ? Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 10,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recording  $_recordingLabel',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => onSend(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.only(
                        left: 15,
                        right: 4,
                        top: 11,
                        bottom: 11,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Emoji',
                        onPressed: onEmoji,
                        icon: const Icon(
                          Icons.emoji_emotions_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 5),
          if (isSending)
            const SizedBox(
              width: 34,
              height: 34,
              child: Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            _ComposerIcon(
              icon: controller.text.trim().isEmpty
                  ? Icons.thumb_up_rounded
                  : Icons.send_rounded,
              tooltip: controller.text.trim().isEmpty ? 'Send like' : 'Send',
              onTap: controller.text.trim().isEmpty ? onLike : onSend,
            ),
        ],
      ),
    );
  }
}

class _ComposerIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  const _ComposerIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        icon,
        color: onTap == null ? AppColors.lightGrey : color,
        size: 21,
      ),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _EmojiPicker({required this.onSelected});

  static const _emojis = [
    '😀',
    '😂',
    '🥰',
    '😍',
    '😊',
    '😉',
    '😎',
    '😭',
    '😡',
    '🤔',
    '👍',
    '👎',
    '❤️',
    '🔥',
    '🎉',
    '✨',
    '🙏',
    '👏',
    '💯',
    '💕',
    '😅',
    '🥳',
    '🤩',
    '😘',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 155,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GridView.count(
        crossAxisCount: 8,
        children: [
          for (final emoji in _emojis)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(emoji),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final String name;
  const _EmptyChatState({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              "Say hello to $name",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Ask about materials, customization, or delivery.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
