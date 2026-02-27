# 🍋 Lemonade Mobile: local AI server companion app

<table>
  <tr>
    <td>
      <img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/be/17/cb/be17cb07-3e0c-0ea2-06a9-70a7088f05ff/IMG_6296.png/230x499bb.webp" alt="Lemonade Chat Screenshot 1" width="230" />
    </td>
    <td>
      <img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/22/6f/5a/226f5a08-79fd-f148-9802-7af577d2ea69/IMG_6295.png/230x499bb.webp" alt="Lemonade Chat Screenshot 2" width="230" />
    </td>
    <td>
      <img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/14/4b/11/144b1186-8a00-a069-392a-6923f6376420/IMG_6294.png/230x499bb.webp" alt="Lemonade Chat Screenshot 3" width="230" />
    </td>
    <td>
      <img src="https://github.com/user-attachments/assets/f6dd076c-2166-44b6-82b8-00ec851a0ad0" alt="Lemonade Chat Screenshot 4" width="230" />
    </td>
  </tr>
</table>


<h3 align="center">
  <a href="https://apps.apple.com/us/app/lemonade-mobile/id6757372210">iPhone/iPad</a> | 
  Android: Coming Soon | 
  <a href="https://discord.gg/5xXzkMu8Zk">Discord</a>
</h3>


Lemonade Mobile is a polished chat interface for [Lemonade AI servers](https://github.com/lemonade-sdk/lemonade) with syntax highlighting and multi-server support. Start your server, connect this app, and take your Lemonade to go. 

A Lemonade Open Source Project - maintained by [Geramy Loveless](https://github.com/Geramy).

## Features

- **Multi-Server Support**: Connect to multiple Lemonade/OpenAI-compatible servers
- **Code Syntax Highlighting**: Beautiful code rendering with language detection
- **Streaming Responses**: Real-time chat with live text streaming
- **Dark Theme**: Modern dark UI that's easy on the eyes
- **Persistent Chat History**: Never lose your conversations
- **Cross-Platform**: Works on mobile and desktop

## Quick Start

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run
```

## Configuration

### Adding AI Servers

1. Launch the app and tap the settings gear icon
2. Add your server details:
   - **Name**: Something descriptive like "My Local Server"
   - **URL**: Your server endpoint (e.g., `http://192.168.1.10:8000/api`) - Later will be changed to be user friendly.
   - **API Key**: Optional, defaults to "lemonade" if empty

### Testing Connections

Use the checkmark button next to each server to verify connectivity before chatting.

## How to Use

- **Server Selection**: Pick your AI server from the top dropdown
- **Model Selection**: Expand the drawer menu to choose different models
- **Chat Interface**:
  - Type your message and hit send
  - Watch responses stream in real-time
  - Code blocks get automatic syntax highlighting
- **Copy Functions**:
  - Long-press any message to copy it entirely
  - Tap the copy icon on code blocks to copy just that code
- **Chat Management**:
  - Create new conversations from the drawer
  - Switch between chat threads
  - Delete old conversations you don't need

## Tech Stack

- **Framework**: Flutter with Material Design 3
- **State Management**: Riverpod for clean architecture
- **Persistence**: SharedPreferences for local storage
- **API Integration**: dart_openai for OpenAI-compatible endpoints
- **UI Polish**: Custom themes and smooth animations

## Project Layout

```
lib/
├── main.dart                 # App bootstrap & routing
├── models/                   # Data structures
│   ├── server_config.dart    # Server connection details
│   ├── chat_message.dart     # Message format
│   └── chat_history.dart     # Conversation management
├── providers/                # State management
│   ├── servers_provider.dart # Server list & selection
│   ├── chat_provider.dart    # Active conversation
│   ├── chat_history_provider.dart # Saved conversations
│   └── models_provider.dart  # Available AI models
├── screens/                  # Main UI screens
│   ├── chat_screen.dart      # Main chat interface
│   └── settings_screen.dart  # Server configuration
├── services/                 # External integrations
│   └── openai_service.dart   # AI API communication
├── widgets/                  # Reusable UI components
│   ├── chat_input.dart       # Message composition
│   ├── message_bubble.dart   # Message display with code highlighting
│   ├── server_selector.dart  # Server picker
│   └── chat_drawer.dart      # Navigation sidebar
└── utils/                    # Shared utilities
    └── constants.dart        # Theme & styling constants
```

### This project is licensed as MIT
