# Meka Personal Assistant

Meka is a secure, modular personal assistant built with Flutter for Android, Windows, and Linux.

## Features
- **Cross-Platform**: Runs natively on Desktop and Mobile.
- **Voice Interface**: Audio recording and TTS integration.
- **Local Intelligence**: Set up to connect to local LLM instances (like Ollama).
- **Skill System**: Easily extend Meka's capabilities by adding new Dart classes extending `SkillBase`.

## Setup Instructions

1. Ensure you have [Flutter installed](https://docs.flutter.dev/get-started/install).
2. Since we created the core code directly, you need to generate the native platform files. Run the following command in the root directory:
   ```bash
   flutter create --platforms=android,windows,linux .
   ```
3. Fetch dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run -d windows
   ```

## Custom Skills
To add a new capability:
1. Create a new file in `lib/skills/` extending `SkillBase`.
2. Implement `canHandle(String input)` to define when your skill triggers.
3. Implement `execute(String input)` to perform the action.
4. Register the skill in `lib/skills/skill_router.dart`.

## Security Note
This assistant uses standard API constraints and relies on user-consented permissions. It avoids unconditionally requesting dangerous permissions or auto-elevating privileges, ensuring your host system remains secure.
