/// Lemonade / OpenAI-compatible API client.
///
/// Use [LemonadeApiClient] as the entry point. Typed request/response objects
/// live under `types/`. Tool-call streaming and SSE machinery under `sse/`.
/// WebSocket protocols (audio realtime, logs) under `realtime/`.
library;

export 'exceptions.dart';
export 'http_errors.dart';
export 'lemonade_client.dart';
export 'net.dart';
export 'url_utils.dart';
export 'sse/sse_parser.dart';
export 'sse/tool_call_assembler.dart';
export 'types/audio_request.dart';
export 'types/audio_response.dart';
export 'types/chat_message.dart';
export 'types/chat_request.dart';
export 'types/chat_response.dart';
export 'types/image_request.dart';
export 'types/image_response.dart';
export 'types/model_info.dart';
export 'types/tool_call.dart';
export 'types/tool_definition.dart';
export 'endpoints/admin_endpoint.dart';
export 'endpoints/audio_endpoint.dart';
export 'endpoints/chat_endpoint.dart';
export 'endpoints/images_endpoint.dart';
export 'endpoints/models_endpoint.dart';
export 'realtime/logs_socket.dart';
export 'realtime/realtime_audio_socket.dart';
