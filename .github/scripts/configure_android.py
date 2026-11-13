from pathlib import Path
import re

APP_ID = "com.example.my_finance"
gradle = Path("android/app/build.gradle.kts")
if not gradle.exists():
    raise SystemExit("Expected generated android/app/build.gradle.kts; Android project generation failed")
text = gradle.read_text()
text = re.sub(r'namespace\s*=\s*"[^"]+"', f'namespace = "{APP_ID}"', text, count=1)
text = re.sub(r'applicationId\s*=\s*"[^"]+"', f'applicationId = "{APP_ID}"', text, count=1)
text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
if "signingConfigs {" not in text:
    signing = """    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") ?: "upload-keystore.jks")
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

"""
    text = text.replace("android {\n", "android {\n" + signing, 1)
text, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', text, count=1)
if n == 0 and 'signingConfig = signingConfigs.getByName("release")' not in text:
    raise SystemExit("Release build type has no supported release signing configuration")
if 'create("release")' not in text:
    raise SystemExit("Release signing configuration is missing")
if f'applicationId = "{APP_ID}"' not in text or f'namespace = "{APP_ID}"' not in text:
    raise SystemExit("Could not enforce stable Android application ID")
gradle.write_text(text)

activities = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not activities:
    raise SystemExit("Generated MainActivity.kt was not found")
for activity in activities:
    content = activity.read_text()
    content = content.replace("import io.flutter.embedding.android.FlutterActivity", "import io.flutter.embedding.android.FlutterFragmentActivity")
    content = re.sub(r":\s*FlutterActivity\b", ": FlutterFragmentActivity", content)
    if "FlutterFragmentActivity" not in content:
        raise SystemExit("Could not configure FlutterFragmentActivity for local_auth")
    activity.write_text(content)

manifest = Path("android/app/src/main/AndroidManifest.xml")
content = manifest.read_text()
permission = '    <uses-permission android:name="android.permission.INTERNET" />\n'
if "android.permission.INTERNET" not in content:
    content = content.replace("<application", permission + "    <application", 1)
manifest.write_text(content)

wrapper = Path("android/gradle/wrapper/gradle-wrapper.properties")
if wrapper.exists():
    wrapper.write_text(wrapper.read_text().replace("services.gradle.org/distributions/", "downloads.gradle.org/distributions/"))

ignore = Path(".gitignore")
lines = ignore.read_text().splitlines() if ignore.exists() else []
for item in ["build/", ".dart_tool/", ".flutter-plugins", ".flutter-plugins-dependencies", "android/.gradle/", "android/local.properties", "android/key.properties", "android/app/*.jks"]:
    if item not in lines:
        lines.append(item)
ignore.write_text("\n".join(lines).rstrip() + "\n")
print(f"Android configuration locked to {APP_ID}; release signing uses persistent GitHub Actions secrets.")
