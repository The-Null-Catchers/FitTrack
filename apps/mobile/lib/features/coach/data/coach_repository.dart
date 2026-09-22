import '../../../core/network/api_client.dart';
import '../../programs/domain/program.dart';
import '../domain/coach_models.dart';

/// FitCoach endpoints.
class CoachRepository {
  const CoachRepository(this._client);

  final ApiClient _client;

  Future<({String conversationId, CoachMessage message, String disclaimer})>
      chat({
    required String message,
    String? conversationId,
    bool includeContext = true,
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/ai/chat',
      data: <String, dynamic>{
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        'include_context': includeContext,
      },
    );
    return (
      conversationId: body['conversation_id'] as String,
      message: CoachMessage.fromJson(
        Map<String, dynamic>.from(body['message'] as Map<dynamic, dynamic>),
      ),
      disclaimer: body['disclaimer'] as String? ?? '',
    );
  }

  Future<List<CoachConversation>> conversations() async {
    final List<dynamic> body =
        await _client.get<List<dynamic>>('/api/v1/ai/conversations');
    return body
        .map((dynamic item) => CoachConversation.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<CoachConversation> conversation(String id) async {
    final Map<String, dynamic> body =
        await _client.get<Map<String, dynamic>>('/api/v1/ai/conversations/$id');
    return CoachConversation.fromJson(body);
  }

  Future<void> deleteConversation(String id) =>
      _client.delete<void>('/api/v1/ai/conversations/$id');

  /// Generate a plan preview. Nothing is persisted until [savePlan].
  Future<GeneratedPlan> generatePlan(PlanRequest request) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/ai/plans/generate',
      data: request.toJson(),
    );
    return GeneratedPlan.fromResponse(body);
  }

  /// Save a previewed plan as a *new* program; nothing existing is overwritten.
  Future<Program> savePlan({
    required String generationId,
    String? name,
    bool activate = false,
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/ai/plans/save',
      data: <String, dynamic>{
        'generation_id': generationId,
        if (name != null) 'name': name,
        'activate': activate,
      },
    );
    return Program.fromJson(body);
  }

  Future<List<Map<String, dynamic>>> substitutions({
    required String exerciseId,
    required List<String> equipment,
    int limit = 5,
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/ai/substitutions',
      data: <String, dynamic>{
        'exercise_id': exerciseId,
        'available_equipment': equipment,
        'limit': limit,
      },
    );
    return ((body['options'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic item) =>
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> progressSummary(String range) =>
      _client.get<Map<String, dynamic>>(
        '/api/v1/ai/progress-summary',
        query: <String, dynamic>{'range': range},
      );

  Future<Map<String, dynamic>> usage() =>
      _client.get<Map<String, dynamic>>('/api/v1/ai/usage');
}
