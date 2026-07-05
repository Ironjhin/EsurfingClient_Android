# ESurfing KeepAliveService 必须保持原名,AndroidManifest.xml 显式引用
-keep class com.example.esurfing_client.KeepAliveService { *; }
-keep class com.example.esurfing_client.MainActivity { *; }

# Flutter 相关类不要混淆
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
