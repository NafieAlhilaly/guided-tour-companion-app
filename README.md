# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## MQTT pages

This project includes a simple MQTT demo:

- Open **MQTT Connect** from the main screen.
- Enter the broker host (and port if non-default) and tap **Connect**.
- On successful connection you'll be taken to the **MQTT Messages** page where you can:
  - Subscribe to topics (e.g. `#` or `test/#`).
  - Send messages to a topic.
  - View incoming messages in real time.

The implementation is in:

- `lib/services/mqtt_service.dart` — singleton service that manages the MQTT client and exposes a `messages` stream.
- `lib/pages/mqtt_connect_page.dart` — connect UI.
- `lib/pages/mqtt_messages_page.dart` — subscribe/publish and message list.

