import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const githubApi = 'https://api.github.com';
const username = 'kenjiz';

Future<void> main() async {
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token == null) {
    print('ERROR: Missing GITHUB_TOKEN environment variable.');
    exit(1);
  }

  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
  };

  // FETCH REPOS (with pagination)
  List repos = [];
  int page = 1;

  while (true) {
    final res = await http.get(
      Uri.parse('$githubApi/users/$username/repos?per_page=100&page=$page'),
      headers: headers,
    );

    final data = jsonDecode(res.body);

    if (data is List && data.isNotEmpty) {
      repos.addAll(data);
      page++;
    } else {
      break;
    }
  }

  final repoCount = repos.length;

  // FETCH STATS FOR COMMITS / ADDITIONS / DELETIONS
  int totalCommits = 0;
  int totalAdd = 0;
  int totalDel = 0;

  for (final repo in repos) {
    final repoName = repo['name'];
    final statsUrl = '$githubApi/repos/$username/$repoName/stats/contributors';

    final statsRes = await http.get(Uri.parse(statsUrl), headers: headers);

    if (statsRes.statusCode == 202) {
      continue; // still generating stats
    }

    if (statsRes.statusCode == 200) {
      final stats = jsonDecode(statsRes.body);

      if (stats is List) {
        final userStats = stats.firstWhere(
          (s) => s['author']['login'] == username,
          orElse: () => null,
        );

        if (userStats != null) {
          for (final week in userStats['weeks']) {
            totalCommits += week['c'] as int;
            totalAdd += week['a'] as int;
            totalDel += week['d'] as int;
          }
        }
      }
    }
  }

  final totalLoc = totalAdd + totalDel;

  // UPDATE EXISTING SVG FILES
  await updateSvg(
    'light_mode.svg',
    repoCount,
    totalCommits,
    totalLoc,
    totalAdd,
    totalDel,
  );

  await updateSvg(
    'dark_mode.svg',
    repoCount,
    totalCommits,
    totalLoc,
    totalAdd,
    totalDel,
  );

  print('✔ Updated light_mode.svg & dark_mode.svg successfully');
}

// FUNCTION: Update SVG content by ID
Future<void> updateSvg(
  String path,
  int repoCount,
  int commitCount,
  int totalLoc,
  int locAdd,
  int locDel,
) async {
  final file = File(path);

  if (!file.existsSync()) {
    print('⚠ SVG not found: $path (SKIPPED)');
    return;
  }

  String svg = await file.readAsString();

  // Format numbers with commas
  String fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );

  final updates = {
    'repo_data': fmt(repoCount),
    'commit_data': fmt(commitCount),
    'loc_data': fmt(totalLoc),
    'loc_add': fmt(locAdd),
    'loc_del': fmt(locDel),
  };

  // Replace <tspan id="">value</tspan>
  updates.forEach((id, value) {
    svg = svg.replaceAllMapped(
      RegExp(r'(<tspan[^>]*id="' + id + r'"[^>]*>)([^<]*)(</tspan>)'),
      (match) => '${match[1]}$value${match[3]}',
    );
  });

  await file.writeAsString(svg);
  print('✔ Updated $path');
}
