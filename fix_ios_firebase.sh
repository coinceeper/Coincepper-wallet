#!/bin/bash
# 🍎 iOS Firebase Configuration Fix Script
# اسکریپت حل مشکل Firebase در iOS

echo "🍎 شروع اصلاح تنظیمات Firebase در iOS..."

# Step 1: Flutter Clean
echo "1️⃣ پاک کردن Flutter cache..."
flutter clean

# Step 2: Clean iOS
echo "2️⃣ پاک کردن iOS Pods..."
cd ios
rm -rf Pods/
rm -f Podfile.lock
cd ..

# Step 3: Pub Get
echo "3️⃣ نصب مجدد dependencies..."
flutter pub get

# Step 4: Pod Install
echo "4️⃣ نصب مجدد iOS Pods..."
cd ios
pod install
cd ..

# Step 5: Check Bundle ID
echo "5️⃣ بررسی Bundle ID..."
BUNDLE_ID_INFO=$(grep -A1 "CFBundleIdentifier" ios/Runner/Info.plist | grep -o "com\.[^<]*")
BUNDLE_ID_PLIST=$(grep -A1 "BUNDLE_ID" ios/Runner/GoogleService-Info.plist | grep -o "com\.[^<]*")

echo "   Info.plist Bundle ID: $BUNDLE_ID_INFO"
echo "   GoogleService-Info.plist Bundle ID: $BUNDLE_ID_PLIST"

if [ "$BUNDLE_ID_INFO" = "$BUNDLE_ID_PLIST" ]; then
    echo "✅ Bundle IDs match!"
else
    echo "❌ Bundle IDs don't match!"
fi

# Step 6: Check Firebase Files
echo "6️⃣ بررسی فایل‌های Firebase..."

if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    echo "✅ GoogleService-Info.plist found"
else
    echo "❌ GoogleService-Info.plist NOT found"
fi

if [ -f "lib/firebase_options.dart" ]; then
    echo "✅ firebase_options.dart found"
else
    echo "❌ firebase_options.dart NOT found"
fi

# Step 7: Build iOS (optional)
echo "7️⃣ آماده‌سازی build iOS..."
flutter build ios --debug --no-codesign

echo ""
echo "🎉 اصلاح تنظیمات تمام شد!"
echo ""
echo "📱 برای تست:"
echo "   flutter run -d ios"
echo ""
echo "🔍 برای تست نوتیفیکیشن:"
echo "   python test_notifications.py [FCM_TOKEN]"
echo ""
echo "📋 در صورت مشکل، فایل IOS_FIREBASE_CONFIGURATION_FIX.md را مطالعه کنید" 