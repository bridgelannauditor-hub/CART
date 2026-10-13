# LIVE shopping

The current implementation builds on the existing Agora test channel and adds a Firestore-backed commerce and interaction layer.

Implemented:

- Seller camera and microphone broadcast through Agora
- Shop products available from the viewer's Shop button
- Seller product pinning with a real-time pinned-product card
- Product detail and normal cart/checkout flow from LIVE
- Real-time customer comments and seller replies
- Comment pause/resume, comment hiding, and viewer blocking
- Repeatable heart reactions and live reaction count
- Approximate connected-viewer count from Agora callbacks
- Notifications for current followers when Agora confirms the stream
- Notification deep link while the seller is still live
- Broadcast IDs so comments from earlier sessions do not appear in a new LIVE
- Session end metadata for LIVE history

Production limits:

- Agora still uses the single development channel and temporary token in `agora_config.dart`. Concurrent seller streams require a token service that issues a unique channel and token per seller/session.
- Co-host video needs dynamic broadcaster tokens, camera/microphone permission flows for guests, host approval, and multi-video layout. It is intentionally not represented as available until that backend exists.
- Replay needs Agora Cloud Recording or another recording/storage pipeline. The app stores session metadata, but does not claim that a video replay exists.
- Firestore security rules are not included in this repository. Production rules must enforce session ownership, message sender identity, moderation rights, and allowed reaction writes.
