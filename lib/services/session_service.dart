import '../core/rpc_error.dart';
import '../core/supabase_client.dart';

// Result of start_session: the session id, the first QR token, and
// whether today's earlier class was reopened (resumed) instead of new.
class StartedSession {
  final String sessionId;
  final String qrToken;
  final bool resumed;
  StartedSession(this.sessionId, this.qrToken, {this.resumed = false});
}

// All server calls (RPCs) for a class session.
// The server does all the checking; the app only calls and shows the result.
class SessionService {
  // Start a class. The server creates a session and the first QR token.
  Future<StartedSession> startSession(String courseId) async {
    final data = await _callRpc('start_session', {'p_course_id': courseId});
    // Response: {ok, code: 'STARTED', session_id, token, expires_at, resumed}
    // resumed = true when today's earlier class of this course was reopened
    // (sql/session_resume_same_day.sql). Missing = a new class.
    return StartedSession(
      _readString(data, 'session_id', 'start_session'),
      _readToken(data, 'start_session'),
      resumed: data['resumed'] == true,
    );
  }

  // Get a new QR token (the teacher screen calls this every 30 seconds).
  Future<String> refreshQrToken(String sessionId) async {
    final data =
        await _callRpc('refresh_qr_token', {'p_session_id': sessionId});
    return _readToken(data, 'refresh_qr_token');
  }

  // End the class.
  Future<void> endSession(String sessionId) async {
    await _callRpc('end_session', {'p_session_id': sessionId});
  }

  // Every RPC returns JSON like {ok, code, ...}.
  // If ok is not true, we throw an RpcException with the server's code.
  Future<Map<String, dynamic>> _callRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final result = await supabase.rpc(functionName, params: params);

    if (result is! Map) {
      throw FormatException(
          '$functionName returned an unexpected response: $result');
    }
    final data = Map<String, dynamic>.from(result);

    if (data['ok'] != true) {
      throw RpcException((data['code'] ?? 'UNKNOWN').toString());
    }
    return data;
  }

  // The server sends the QR token under the key "token".
  // "qr_token" is accepted as a fallback in case a function uses that name.
  String _readToken(Map<String, dynamic> data, String function) {
    if (data['token'] != null) return data['token'].toString();
    return _readString(data, 'qr_token', function);
  }

  // Reads a required text field from an RPC response.
  // If it is missing, the error shows the full response so we can fix it.
  String _readString(Map<String, dynamic> data, String key, String function) {
    final value = data[key];
    if (value == null) {
      throw FormatException('$function response has no "$key": $data');
    }
    return value.toString();
  }
}
