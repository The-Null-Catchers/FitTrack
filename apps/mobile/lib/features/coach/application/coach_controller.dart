import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/coach_repository.dart';
import '../domain/coach_models.dart';

final Provider<CoachRepository> coachRepositoryProvider =
    Provider<CoachRepository>((Ref ref) {
  return CoachRepository(ref.watch(apiClientProvider));
});

@immutable
class CoachState {
  const CoachState({
    this.messages = const <CoachMessage>[],
    this.conversationId,
    this.isSending = false,
    this.errorMessage,
    this.disclaimer = '',
  });

  final List<CoachMessage> messages;
  final String? conversationId;
  final bool isSending;
  final String? errorMessage;
  final String disclaimer;

  bool get isEmpty => messages.isEmpty;

  CoachState copyWith({
    List<CoachMessage>? messages,
    String? conversationId,
    bool? isSending,
    String? errorMessage,
    String? disclaimer,
    bool clearError = false,
  }) =>
      CoachState(
        messages: messages ?? this.messages,
        conversationId: conversationId ?? this.conversationId,
        isSending: isSending ?? this.isSending,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        disclaimer: disclaimer ?? this.disclaimer,
      );
}

class CoachController extends StateNotifier<CoachState> {
  CoachController(this._ref) : super(const CoachState());

  final Ref _ref;

  CoachRepository get _repository => _ref.read(coachRepositoryProvider);

  /// Send a message, showing it optimistically while the reply is in flight.
  Future<void> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    final CoachMessage pending = CoachMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
      isPending: true,
    );
    state = state.copyWith(
      messages: <CoachMessage>[...state.messages, pending],
      isSending: true,
      clearError: true,
    );

    try {
      final ({
        String conversationId,
        CoachMessage message,
        String disclaimer
      }) result = await _repository.chat(
        message: trimmed,
        conversationId: state.conversationId,
      );
      state = CoachState(
        messages: <CoachMessage>[
          ...state.messages.map(
            (CoachMessage message) =>
                message.id == pending.id ? _confirm(message) : message,
          ),
          result.message,
        ],
        conversationId: result.conversationId,
        disclaimer: result.disclaimer,
      );
    } on ApiException catch (error) {
      // Drop the optimistic bubble so the user can edit and retry.
      state = state.copyWith(
        messages: state.messages
            .where((CoachMessage message) => message.id != pending.id)
            .toList(),
        isSending: false,
        errorMessage: error.message,
      );
    }
  }

  CoachMessage _confirm(CoachMessage message) => CoachMessage(
        id: message.id,
        role: message.role,
        content: message.content,
        createdAt: message.createdAt,
        safetyRedirect: message.safetyRedirect,
        payload: message.payload,
      );

  Future<void> openConversation(String id) async {
    state = const CoachState(isSending: true);
    try {
      final CoachConversation conversation = await _repository.conversation(id);
      state = CoachState(
        messages: conversation.messages,
        conversationId: conversation.id,
      );
    } on ApiException catch (error) {
      state = CoachState(errorMessage: error.message);
    }
  }

  void startNewConversation() => state = const CoachState();

  void clearError() => state = state.copyWith(clearError: true);
}

final StateNotifierProvider<CoachController, CoachState> coachProvider =
    StateNotifierProvider<CoachController, CoachState>(
  (Ref ref) => CoachController(ref),
);

final FutureProvider<List<CoachConversation>> coachConversationsProvider =
    FutureProvider<List<CoachConversation>>((Ref ref) {
  return ref.watch(coachRepositoryProvider).conversations();
});

/// State for the guided plan generator.
@immutable
class PlanGeneratorState {
  const PlanGeneratorState({
    required this.request,
    this.plan,
    this.isGenerating = false,
    this.isSaving = false,
    this.errorMessage,
  });

  final PlanRequest request;
  final GeneratedPlan? plan;
  final bool isGenerating;
  final bool isSaving;
  final String? errorMessage;

  PlanGeneratorState copyWith({
    PlanRequest? request,
    GeneratedPlan? plan,
    bool? isGenerating,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool clearPlan = false,
  }) =>
      PlanGeneratorState(
        request: request ?? this.request,
        plan: clearPlan ? null : (plan ?? this.plan),
        isGenerating: isGenerating ?? this.isGenerating,
        isSaving: isSaving ?? this.isSaving,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class PlanGeneratorController extends StateNotifier<PlanGeneratorState> {
  PlanGeneratorController(this._ref, PlanRequest initial)
      : super(PlanGeneratorState(request: initial));

  final Ref _ref;

  void updateRequest(PlanRequest request) =>
      state = state.copyWith(request: request, clearError: true);

  Future<void> generate() async {
    state =
        state.copyWith(isGenerating: true, clearError: true, clearPlan: true);
    try {
      final GeneratedPlan plan =
          await _ref.read(coachRepositoryProvider).generatePlan(state.request);
      state = state.copyWith(plan: plan, isGenerating: false);
    } on ApiException catch (error) {
      state = state.copyWith(isGenerating: false, errorMessage: error.message);
    }
  }

  /// Save the preview as a new program. Returns the new program's id.
  Future<String?> save({String? name, bool activate = false}) async {
    final GeneratedPlan? plan = state.plan;
    if (plan == null) return null;

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final String id = (await _ref.read(coachRepositoryProvider).savePlan(
                generationId: plan.generationId,
                name: name,
                activate: activate,
              ))
          .id;
      state = state.copyWith(isSaving: false);
      return id;
    } on ApiException catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      return null;
    }
  }
}

final StateNotifierProviderFamily<PlanGeneratorController, PlanGeneratorState,
        PlanRequest> planGeneratorProvider =
    StateNotifierProvider.family<PlanGeneratorController, PlanGeneratorState,
        PlanRequest>(
  (Ref ref, PlanRequest initial) => PlanGeneratorController(ref, initial),
);
