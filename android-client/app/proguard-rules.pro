# ProGuard / R8 configuration for DisplayMac Android client.
-keep class com.displaymac.client.protocol.** { *; }
-keep class com.displaymac.client.ui.AuroraBackgroundView {
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
