import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import '../data/routing_repository_impl.dart';
import '../domain/routing_repository.dart';

final _dioProvider = Provider((ref) => ApiClient.create());

final routingRepositoryProvider = Provider<RoutingRepository>((ref) {
  return RoutingRepositoryImpl(ref.watch(_dioProvider));
});
