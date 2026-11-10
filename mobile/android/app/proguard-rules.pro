# SQLCipher (sqflite_sqlcipher) uses JNI: keep its classes.
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-dontwarn net.sqlcipher.**
-keep class com.davidmartos96.sqflite_sqlcipher.** { *; }
