# Правила R8 для релізу. Усе, що читається рефлексією або через JNI, називаємо явно.

-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# kotlinx.serialization: серіалізатори @Serializable-класів шукаються за іменем.
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class app.poruch.**$$serializer { *; }
-keepclassmembers class app.poruch.** { *** Companion; }
-keepclasseswithmembers class app.poruch.** { kotlinx.serialization.KSerializer serializer(...); }
-dontnote kotlinx.serialization.**
-dontwarn kotlinx.serialization.**

# Ktor / OkHttp / slf4j: опційні залежності, яких у збірці нема.
-dontwarn io.ktor.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.slf4j.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn java.lang.management.**
-keep class io.ktor.client.engine.okhttp.** { *; }

# MapLibre: нативний код звертається до Java-класів через JNI.
-keep class org.maplibre.** { *; }
-dontwarn org.maplibre.**

# Firebase: сервіс пушів створюється системою за іменем із маніфесту.
-keep class app.poruch.android.platform.PushService { *; }
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.**

# Koin: клас Application із маніфесту.
-keep class app.poruch.android.PoruchApplication { *; }

# SQLDelight android-driver спирається на androidx.sqlite; без рефлексії, лише dontwarn.
-dontwarn androidx.sqlite.**

# Coroutines: службові класи, які ProGuard не бачить.
-dontwarn kotlinx.coroutines.**
