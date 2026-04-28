# Required Privacy Settings

## Speech Recognition Permission

Add this to your `Info.plist` file:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>We use speech recognition to transcribe your French audio files so you can read along.</string>
```

## How to Add:

1. In Xcode, select your project in the navigator
2. Select your app target
3. Go to the **Info** tab
4. Click the **+** button to add a new key
5. Type: `NSSpeechRecognitionUsageDescription` (or search for "Speech Recognition")
6. Set the value to: `We use speech recognition to transcribe your French audio files so you can read along.`

Alternatively, if you have an `Info.plist` file in your project:
1. Right-click it and choose **Open As** → **Source Code**
2. Add the XML above inside the `<dict>` tag
3. Save the file
