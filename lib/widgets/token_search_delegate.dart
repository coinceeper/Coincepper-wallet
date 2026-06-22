import 'package:flutter/material.dart';
import '../providers/view_models/home_view_model.dart';

/// Search delegate for token search in HomeScreen.
///
/// Extracted from HomeScreen to reduce HomeScreen's responsibility and
/// make the search logic independently testable.
class TokenSearchDelegate extends SearchDelegate<String?> {
  final HomeViewModel viewModel;

  TokenSearchDelegate(this.viewModel);

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = viewModel.searchTokens(query);

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final token = results[index];
        return ListTile(
          leading: Icon(
            Icons.monetization_on,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(token.symbol ?? ''),
          subtitle: Text(token.name ?? ''),
          onTap: () {
            close(context, token.symbol);
          },
        );
      },
    );
  }
}
