# Play Store Publishing Guide for Credilo

## Prerequisites
- Google Play Console account ($25 one-time fee)
- Flutter SDK installed
- Android SDK installed

## Step 1: Create Signing Keystore

Run this command in your terminal (replace with your actual details):

```bash
cd android/app
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Important:**
- Choose strong passwords for both keystore and key
- Save these passwords securely - you'll need them for all future updates
- Answer the certificate questions (name, organization, etc.)
- The keystore file will be created at `android/app/upload-keystore.jks`

## Step 2: Configure key.properties

Edit `android/key.properties` and replace:
- `YOUR_STORE_PASSWORD` with your keystore password
- `YOUR_KEY_PASSWORD` with your key password

The file should look like:
```
storePassword=your_actual_store_password
keyPassword=your_actual_key_password
keyAlias=upload
storeFile=upload-keystore.jks
```

## Step 3: Update App Version

In `pubspec.yaml`, update the version:
```yaml
version: 1.0.0+1
```
- Format: `MAJOR.MINOR.PATCH+BUILD_NUMBER`
- `BUILD_NUMBER` must increment for each Play Store upload
- For example: `1.0.1+2` for the next release

## Step 4: Build Release Bundle (AAB)

**Play Store requires AAB format (not APK):**

```bash
flutter build appbundle --release
```

The AAB file will be at:
`build/app/outputs/bundle/release/app-release.aab`

## Step 5: Test the Release Build Locally (Optional)

To test before uploading:
```bash
flutter build apk --release
flutter install --release
```

## Step 6: Play Console Setup

### 6.1 Create App in Play Console
1. Go to https://play.google.com/console
2. Click "Create app"
3. Fill in:
   - App name: **Credilo**
   - Default language: Your primary language
   - App or game: App
   - Free or paid: Choose your model
   - Accept declarations

### 6.2 Complete Store Listing

**Required:**
- App name: Credilo
- Short description (80 chars max)
- Full description (4000 chars max)
- App icon: 512x512px PNG (no transparency)
- Feature graphic: 1024x500px PNG
- Screenshots:
  - Phone: At least 2, max 8 (16:9 or 9:16)
  - Tablet (optional): 7" and 10"
- Category: Business/Finance
- Contact details: Email, phone, website

**Optional but recommended:**
- Promo video (YouTube)
- Promo graphic

### 6.3 Content Rating
- Complete the questionnaire
- Get rating certificate (required)

### 6.4 Privacy Policy
- Required if your app collects user data
- Create a privacy policy page
- Add URL in Play Console

### 6.5 Target Audience & Content
- Set target age group
- Complete content rating questionnaire

## Step 7: Upload AAB

1. Go to **Production** (or **Internal testing** / **Closed testing** first)
2. Click **Create new release**
3. Upload `app-release.aab`
4. Add release notes (what's new in this version)
5. Review and roll out

## Step 8: Review Process

- Google reviews within 1-7 days
- You'll get email notifications
- Check Play Console for status updates

## Step 9: Future Updates

For each update:
1. Increment version in `pubspec.yaml` (bump BUILD_NUMBER)
2. Build new AAB: `flutter build appbundle --release`
3. Upload to Play Console
4. Add release notes

**Important:** Always use the SAME keystore file for updates!

## Troubleshooting

### "Upload failed: You need to use a different package name"
- Your package name `com.zyntelx.credilo` is already taken
- Change `applicationId` in `android/app/build.gradle.kts`

### "App not signed with upload key"
- Make sure `key.properties` has correct passwords
- Verify keystore file exists at `android/app/upload-keystore.jks`

### Build errors
- Run `flutter clean` then `flutter pub get`
- Check `flutter doctor` for issues

## Security Notes

- **NEVER commit** `key.properties` or `*.jks` files to git (already in .gitignore)
- Backup your keystore file securely
- If you lose the keystore, you CANNOT update the app - you'll need to publish a new app

## Quick Reference Commands

```bash
# Build release bundle
flutter build appbundle --release

# Build release APK (for testing)
flutter build apk --release

# Clean build
flutter clean && flutter pub get

# Check Flutter setup
flutter doctor
```

## Next Steps After Publishing

1. Set up **Internal testing** track for beta testing
2. Configure **App signing by Google Play** (recommended)
3. Set up **Pre-launch report** for automatic testing
4. Monitor **Crash reports** and **User feedback**

