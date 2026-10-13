/// Configuration for Agora live streaming.
///
/// The App ID identifies your Agora project. The temp token below
/// authorizes joining the test channel named [testChannelName] and
/// expires 24 hours after it was generated. When it goes stale, joining
/// fails, so regenerate it from the Agora Console:
///   Project -> Credentials -> Generate Temp Token
/// and use EXACTLY the channel name in [testChannelName] when generating.
///
/// This is fine for development, but isn't how the real "Go Live"
/// feature will work: in production, each seller's stream needs its own
/// channel (for example, `shop_<sellerId>`), and tokens for those dynamic
/// channel names need to come from a small token-generating server
/// instead of a hardcoded value here.
class AgoraConfig {
  static const String appId = "48d3b4d103364d99ac4b895ff4259d77";

  static const String testChannelName = "test-room";

  /// Paste a freshly generated temp token here.
  static const String testToken =
      "007eJxTYFizsv3K5WVdOzbcYXoaKbPl1R3jjRMlNh2YaHmw8uzHR1f/KDCYWKQYJ5mkGBoYG5uZpFhaJiabJFlYmqalmRiZWqaYmyd+2JfVEMjI8OrmfWZGBggE8TkZSlKLS3SL8vNzGRgAorkncQ==";

  /// False until a real token has been pasted in above, so the live
  /// screens can show a clear message instead of a cryptic failure.
  static bool get hasToken =>
      testToken.isNotEmpty && !testToken.startsWith("PASTE_");
}
