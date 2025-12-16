import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const githubApi = 'https://api.github.com';
const username = 'kenjiz';

Future<void> main() async {
  print('Starting GitHub stats update...');

  final token = Platform.environment['TOKEN'];
  if (token == null) {
    print('ERROR: Missing TOKEN environment variable.');
    exit(1);
  }
  print('✓ Token loaded successfully');

  final headers = {
    'Authorization': 'token $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  // FETCH REPOS using Search API (includes private repos with proper auth)
  print('\nFetching repositories...');
  List repos = [];
  int page = 1;
  final perPage = 100;

  while (true) {
    print('Fetching page $page...');
    final res = await http.get(
      Uri.parse('$githubApi/user/repos?per_page=$perPage&page=$page'),
      headers: headers,
    );

    if (res.statusCode != 200) {
      print('ERROR: API returned ${res.statusCode}');
      break;
    }

    final data = jsonDecode(res.body);

    if (data is List && data.isNotEmpty) {
      repos.addAll(data);
      print('✓ Fetched ${data.length} repositories (total: ${repos.length})');
      page++;
    } else {
      break;
    }
  }

  final repoCount = repos.length;
  print('✓ Total repositories found: $repoCount\n');

  // FETCH STATS FOR COMMITS / ADDITIONS / DELETIONS
  print('Fetching commit statistics...');
  int totalCommits = 0;
  int totalAdd = 0;
  int totalDel = 0;

  int processedRepos = 0;
  for (final repo in repos) {
    final repoFullName = repo['full_name'];
    processedRepos++;
    print('[$processedRepos/$repoCount] Processing: $repoFullName');
    final statsUrl = '$githubApi/repos/$repoFullName/stats/contributors';

    final statsRes = await http.get(
      Uri.parse(statsUrl),
      headers: {
        ...headers,
        'Authorization': 'Bearer $token',
      },
    );

    if (statsRes.statusCode == 202) {
      print('  ⏳ Stats still generating, skipping...');
      continue; // still generating stats
    }

    if (statsRes.statusCode == 200) {
      print('  ✓ Stats fetched successfully');
      final stats = jsonDecode(statsRes.body);

      if (stats is List && stats.isNotEmpty) {
        final userStats = stats.firstWhere(
          (s) => s != null && s['author'] != null && s['author']['login'] == username,
          orElse: () => null,
        );

        if (userStats != null && userStats['weeks'] != null) {
          print('  → Found user contributions');
          for (final week in userStats['weeks']) {
            if (week != null) {
              totalCommits += (week['c'] as int? ?? 0);
              totalAdd += (week['a'] as int? ?? 0);
              totalDel += (week['d'] as int? ?? 0);
            }
          }
        }
      }
    }
  }

  final totalLoc = totalAdd + totalDel;
  print('\n📊 Statistics Summary:');
  print('   Repositories: $repoCount');
  print('   Total Commits: $totalCommits');
  print('   Lines Added: +$totalAdd');
  print('   Lines Deleted: -$totalDel');
  print('   Total LOC: $totalLoc\n');

  // UPDATE EXISTING SVG FILES
  print('Updating SVG files...');
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

  print('\n✅ All SVG files updated successfully!');
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

  print('Processing $path...');
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
