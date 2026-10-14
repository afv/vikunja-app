import 'package:vikunja_app/core/network/response.dart';
import 'package:vikunja_app/domain/entities/project.dart';

abstract class ProjectRepository {
  Future<Response<Project>> create(Project p);

  Future<Response<Project>> get(int projectId);

  Future<Response<List<Project>>> getAll({int page = 1, String? search});

  Future<Response<Project>> update(Project p);

  /// The expression of a saved filter, by its filter id (a saved filter listed as project `-n` has filter id `n - 1`).
  Future<Response<String>> getSavedFilterExpression(int filterId);
}
