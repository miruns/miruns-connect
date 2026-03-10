# Miruns Flutter - Quick Start Guide

Welcome to Miruns Flutter! This guide will help you get started quickly.

## What is Miruns Flutter?

Miruns Flutter is a modern, cross-platform mobile application that integrates:
- 📍 **GPS Tracking** - Real-time location monitoring
- ❤️ **Health Data** - Steps, calories, heart rate, and more
- 📅 **Calendar** - View and manage your workout schedule

## Quick Setup (5 minutes)

### 1. Prerequisites Check
```bash
flutter doctor
```
Ensure you have Flutter 3.9.2+ installed.

### 2. Install Dependencies
```bash
cd miruns_flutter
flutter pub get
```

### 3. Run the App
Choose your platform:

**iOS Simulator:**
```bash
flutter run -d "iPhone 15"
```

**Android Emulator:**
```bash
flutter run -d emulator-5554
```

**Physical Device:**
```bash
flutter devices  # Find your device ID
flutter run -d <device-id>
```

## First Launch

When you first launch the app:

1. **Welcome Screen** - You'll see the Miruns logo and permission requests
2. **Grant Permissions** - Tap "Grant Permissions" button
3. **System Prompts** - Approve:
   - Location access
   - Health/Fitness data
   - Calendar access
4. **Home Screen** - View your dashboard with:
   - Today's steps and calories
   - Current location
   - Calendar events

## Project Structure at a Glance

```
miruns_flutter/
├── lib/
│   ├── core/               # Core functionality
│   │   ├── services/      # Business logic
│   │   ├── theme/         # App styling
│   │   └── router/        # Navigation
│   ├── features/          # Feature modules
│   │   ├── home/         # Main dashboard
│   │   └── permissions/  # Permission flow
│   └── main.dart         # Entry point
```

## Key Features Walkthrough

### 🏠 Home Screen
- **Pull to refresh** - Swipe down to update data
- **Activity Cards** - View steps and calories
- **Location Card** - See current GPS coordinates
- **Calendar Events** - Today's schedule

### ⚙️ Services
Each service is independently configured:
- **HealthService** - Access health metrics
- **LocationService** - Get GPS data
- **CalendarService** - Manage events
- **PermissionService** - Handle all permissions

## Development Tips

### Hot Reload
Make code changes and press `r` in terminal for instant updates.

### Debug Mode
The app runs in debug mode by default with helpful error messages.

### Checking Device Logs
**Android:**
```bash
flutter logs
```

**iOS:**
Open Console app on Mac and filter by device name.

### Common Commands
```bash
# Analyze code
flutter analyze

# Format code
flutter format lib/

# Clean build
flutter clean

# Update dependencies
flutter pub get
```

## Platform-Specific Notes

### iOS
- **First Run**: Open Xcode once to accept licenses
- **Health Data**: Ensure HealthKit capability is enabled
- **Simulator**: Health data may be simulated

### Android
- **Health Connect**: Required for Android 13+ health features
- **Background Location**: Needs "Allow all the time" permission
- **Google Play Services**: Required for location services

## Troubleshooting

### No Health Data Showing
- iOS: Grant HealthKit permissions in Settings → Miruns
- Android: Install Health Connect app

### Location Not Working
- Enable Location Services in device settings
- Grant location permission in app settings

### Calendar Empty
- Add events to your device calendar
- Verify calendar permissions are granted

## Building for Release

### Android APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

### iOS App
```bash
flutter build ios --release
```
Then archive in Xcode for App Store submission.

## Next Steps

1. ✅ Run the app and explore the UI
2. ✅ Test permission flows
3. ✅ View your health data
4. ✅ Add calendar events
5. 🚀 Start customizing for your needs!

## Need Help?

- Check the [README.md](README.md) for detailed documentation
- Review [CHANGELOG.md](CHANGELOG.md) for version history
- See platform-specific setup in README

## Architecture Overview

**State Management:** Riverpod (Provider-based)
**Navigation:** GoRouter (Declarative routing)
**Theme:** Material 3 with custom dark theme
**Structure:** Feature-first organization

## What's Next?

Ideas for extension:
- Add workout tracking
- Implement data visualization
- Create fitness goals
- Add social features
- Sync with wearables

---

**Enjoy building with Miruns Flutter! 🚀**
