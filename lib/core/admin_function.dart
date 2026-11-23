import 'package:supabase_flutter/supabase_flutter.dart';

import 'rpc_error.dart';
import 'supabase_client.dart';

// The admin Edge Function (code: supabase/functions/manage-teacher/index.ts).
// It was deployed from the Supabase dashboard under the name "rapid-task"
// (functions cannot be renamed).
const adminFunctionName = 'rapid-task';

// Calls the admin Edge Function and returns its JSON answer.
// The logged-in admin's token is sent automatically; the function checks it
// and the admin role. Any problem is thrown as an RpcException with a
// readable message.
Future<Map<String, dynamic>> callAdminFunction(
    Map<String, dynamic> body) async {
  try {
    final response =
        await supabase.functions.invoke(adminFunctionName, body: body);
    final data = response.data;
    if (data is Map && data['ok'] == true) {
      return Map<String, dynamic>.from(data);
    }
    throw RpcException(
      (data is Map ? data['code'] : null)?.toString() ?? 'SERVER_ERROR',
      data is Map ? data['message']?.toString() : null,
    );
  } on FunctionsFetchException {
    // No answer at all (no internet, or the function does not exist).
    throw RpcException(
      'FUNCTION_NOT_FOUND',
      'Could not reach the admin service. Check your internet, and that '
          'the "$adminFunctionName" Edge Function is deployed in Supabase.',
    );
  } on FunctionException catch (e) {
    // Non-2xx answers (400, 403, 409, 500 ...) arrive here.
    final details = e.details;
    if (details is Map) {
      throw RpcException(
        (details['code'] ?? 'SERVER_ERROR').toString(),
        details['message']?.toString(),
      );
    }
    if (e.status == 0 || e.status == 404) {
      throw RpcException(
        'FUNCTION_NOT_FOUND',
        'Could not reach the admin service. Deploy the '
            '"$adminFunctionName" Edge Function in Supabase first.',
      );
    }
    throw RpcException(
      'SERVER_ERROR',
      'The admin service answered with error ${e.status}.',
    );
  }
}
