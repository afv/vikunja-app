import 'dart:async';

import 'package:background_downloader/background_downloader.dart'
    show TaskStatusUpdate;
import 'package:vikunja_app/core/network/response.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/domain/entities/task_attachment.dart';
import 'package:vikunja_app/domain/repositories/task_repository.dart';

/// A [TaskRepository] that calls [onChanged] after a task is created, updated or deleted, so local
/// notifications are rescheduled right away instead of at the next background refresh.
class ReschedulingTaskRepository implements TaskRepository {
  final TaskRepository _inner;
  final void Function() onChanged;

  ReschedulingTaskRepository(this._inner, {required this.onChanged});

  void _changed() {
    try {
      onChanged();
    } catch (_) {
      // rescheduling is best effort; the background refresh catches up
    }
  }

  @override
  Future<Response<Task>> add(int projectId, Task task) async {
    final response = await _inner.add(projectId, task);
    if (response.isSuccessful) _changed();
    return response;
  }

  @override
  Future<Response<Task>> update(Task task) async {
    final response = await _inner.update(task);
    if (response.isSuccessful) _changed();
    return response;
  }

  @override
  Future delete(int taskId) async {
    final response = await _inner.delete(taskId);
    _changed();
    return response;
  }

  @override
  Future<Response<Task>> getTask(int id) => _inner.getTask(id);

  @override
  Future<Response<List<String>>> getBucketTitles(int id) =>
      _inner.getBucketTitles(id);

  @override
  Future<Response<List<Task>>> getAllByProject(
    int projectId, [
    Map<String, List<String>>? queryParameters,
  ]) => _inner.getAllByProject(projectId, queryParameters);

  @override
  Future<Response<List<Task>>> getAllByProjectView(
    int projectId,
    int view, [
    Map<String, List<String>>? queryParameters,
  ]) => _inner.getAllByProjectView(projectId, view, queryParameters);

  @override
  Future<Response<List<Task>>> getByFilterString(
    String filterString, [
    Map<String, List<String>>? queryParameters,
  ]) => _inner.getByFilterString(filterString, queryParameters);

  @override
  Future<TaskStatusUpdate> downloadAttachment(
    int taskId,
    TaskAttachment attachment,
  ) => _inner.downloadAttachment(taskId, attachment);

  @override
  Future<String?> getAttachmentFilePath(
    int taskId,
    TaskAttachment attachment,
  ) => _inner.getAttachmentFilePath(taskId, attachment);

  @override
  Future<Response<TaskAttachment>> uploadAttachment(
    int taskId,
    String filePath, {
    String? filename,
  }) => _inner.uploadAttachment(taskId, filePath, filename: filename);
}
