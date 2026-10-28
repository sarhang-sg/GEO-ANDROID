import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'core_failure.dart';
import 'place_repository.dart';
import 'queries.dart';
import 'search_rules.dart';

/// R16 locality candidates and spatial anchors, using build-time postings in
/// the one catalog. Only a page of candidates and eight winners are decoded.
final class LocalitySearchRepository {
  LocalitySearchRepository(Database db, this.rules, this.places) : sql=Queries(db) {
    final version=sql.select("SELECT value FROM metadata WHERE key='searchServiceSchema'");
    if(version.isEmpty || version.single['value']!='1') {
      throw const CoreFailure('search_service_schema','The installed catalog lacks its R16 locality index.');
    }
    db.execute('''CREATE TEMP TABLE locality_candidate(seq INTEGER PRIMARY KEY AUTOINCREMENT,id INTEGER UNIQUE);
      CREATE TEMP TABLE locality_group(g INTEGER,seq INTEGER,id INTEGER,PRIMARY KEY(g,id));
      CREATE INDEX temp.locality_group_identity ON locality_group(id,g);''');
  }
  final Queries sql;
  final SearchRules rules;
  final PlaceRepository places;
  int _count(String language, bool quick, String type, String key) => sql.integer('''
    SELECT count(*) FROM locality_posting p JOIN locality_search s ON s.feature_id=p.feature_id AND s.language=p.language
    WHERE p.language=? AND p.type=? AND p.key=? AND (?=0 OR s.quick=1)''',[language,type,key,quick?1:0]);
  void _appendGroup(int group,String language,bool quick,String type,String key) {
    final offset=sql.integer('SELECT coalesce(max(seq),0) FROM locality_group WHERE g=?',[group]);
    sql.execute('''INSERT OR IGNORE INTO locality_group(g,seq,id)
      SELECT ?,?+row_number() OVER (ORDER BY p.feature_id),p.feature_id FROM locality_posting p
      JOIN locality_search s ON s.language=p.language AND s.feature_id=p.feature_id
      WHERE p.language=? AND p.type=? AND p.key=? AND (?=0 OR s.quick=1) ORDER BY p.feature_id''',
      [group,offset,language,type,key,quick?1:0]);
  }
  int _intersect(List<int> groups) {
    if(groups.isEmpty)return 0;
    var smallest=groups.first,minimum=1<<62;
    for(final g in groups){final count=sql.integer('SELECT count(*) FROM locality_group WHERE g=?',[g]);if(count<minimum){minimum=count;smallest=g;}}
    if(minimum==0)return 0;
    final marks=List.filled(groups.length,'?').join(',');
    sql.execute('''INSERT OR IGNORE INTO locality_candidate(id) SELECT p.id FROM locality_group p
      WHERE p.g=? AND (SELECT count(*) FROM locality_group q WHERE q.id=p.id AND q.g IN ($marks))=? ORDER BY p.seq''',
      [smallest,...groups,groups.length]);
    return sql.integer('SELECT changes()');
  }
  void _candidates(SearchQuery q,String language,bool quick) {
    sql.execute('DELETE FROM locality_candidate');sql.execute('DELETE FROM locality_group');
    final tokens=q.tokens.where((t)=>!q.intentIds.contains(t)).toList();
    if(tokens.isEmpty){_all(language,quick);return;}
    var group=0;
    final exact=<int>[];
    for(final token in tokens){_appendGroup(group,language,quick,'token',token);exact.add(group++);}
    if(_intersect(exact)>0)return;
    final prefixes=<int>[];
    for(final token in tokens){
      final three=token.substring(0,token.length<3?token.length:3),two=token.substring(0,token.length<2?token.length:2);
      final key=_count(language,quick,'prefix',three)>0?three:two;
      if(_count(language,quick,'prefix',key)==0)continue;
      _appendGroup(group,language,quick,'prefix',key);prefixes.add(group++);
    }
    final phonetic=<int>[];
    for(final alternatives in q.phoneticGroups){
      for(final token in alternatives){_appendGroup(group,language,quick,'prefix','~${token.substring(0,2)}');}
      phonetic.add(group++);
    }
    _intersect(prefixes);_intersect(phonetic);
    if(sql.integer('SELECT count(*) FROM locality_candidate')>0)return;
    if(sql.integer('SELECT count(*) FROM locality_search WHERE language=? AND (?=0 OR quick=1)',[language,quick?1:0])<=600)_all(language,quick);
  }
  void _all(String language,bool quick)=>sql.execute('''INSERT INTO locality_candidate(id)
    SELECT feature_id FROM locality_search WHERE language=? AND (?=0 OR quick=1) ORDER BY feature_id''',[language,quick?1:0]);
  Future<void> _yield(bool Function() cancelled) async {
    await Future<void>.delayed(Duration.zero);
    if(cancelled())throw const CoreFailure('cancelled','Search superseded by a newer request.');
  }
  Future<Map<String,Object?>> search(String text,String language,{bool quick=false,bool Function()? cancelled}) async {
    if(!['ku','ar','en'].contains(language)||text.length>4096)throw const CoreFailure('invalid_search','Invalid language or query length.');
    final stop=cancelled??()=>false,q=rules.prepare(text);
    if(q.phrase.length<2&&q.tokens.isEmpty)return {'choices':<Object>[],'anchor':null};
    Map<String,Object?>? anchor;
    final locationTokens=q.tokens.where((t)=>!q.intentIds.contains(t)).toList();
    if(q.intentIds.isNotEmpty&&locationTokens.isNotEmpty){
      final target=rules.normalize(locationTokens.join(' ')),words=SearchRules.words(target);
      if(target.length>=2){
        _candidates(SearchQuery(target,words,[],rules.phonetics(target)),language,quick);
        var after=0;
        while(true){
          final rows=sql.select('''SELECT c.seq,s.names,s.rank,s.population_bonus,f.geometry FROM locality_candidate c
            JOIN locality_search s ON s.feature_id=c.id AND s.language=? JOIN feature f ON f.id=c.id
            WHERE c.seq>? ORDER BY c.seq LIMIT 64''',[language,after]);
          if(rows.isEmpty)break;
          for(final row in rows){
            after=row['seq'] as int;var lexical=0;
            for(final name in List<String>.from(jsonDecode(row['names'] as String) as List)){
              var score=0;
              if(name==target){score=12000;}else if(name.startsWith('$target ')||target.startsWith('$name ')){score=7000;}
              else if(name.contains(target)){score=4000;}else{final covered=words.where(SearchRules.words(name).toSet().contains).length;if(covered==words.length)score=2500+covered*300;}
              if(score>lexical)lexical=score;
            }
            if(lexical==0)continue;
            final score=lexical+(row['rank'] as int)*10+(row['population_bonus'] as num).toDouble();
            if(anchor!=null&&score<=(anchor['score'] as num))continue;
            anchor={'coordinate':(jsonDecode(row['geometry'] as String) as Map)['coordinates'],'score':score};
          }
          await _yield(stop);
        }
      }
    }
    final winners=<({int id,int score})>[];
    if(anchor==null||q.intentIds.isEmpty){
      _candidates(q,language,quick);var after=0;
      while(true){
        final rows=sql.select('''SELECT c.seq,c.id,s.profile,s.rank FROM locality_candidate c JOIN locality_search s
          ON s.feature_id=c.id AND s.language=? WHERE c.seq>? ORDER BY c.seq LIMIT 64''',[language,after]);
        if(rows.isEmpty)break;
        for(final row in rows){
          after=row['seq'] as int;final p=jsonDecode(row['profile'] as String) as Map<String,dynamic>,rank=row['rank'] as int;
          final score=rules.score({'primary_text':p['primary'],'all_text':p['all'],'primary_name':p['primaryName'],'all_names':p['allNames'],'intent':p['intent'],'kind':'place'},q,List<String>.from(p['phoneticKeys'] as List))+rank;
          if(score<=rank)continue;
          var at=0;while(at<winners.length&&winners[at].score>=score){at++;}
          winners.insert(at,(id:row['id'] as int,score:score));if(winners.length>8)winners.removeLast();
        }
        await _yield(stop);
      }
    }
    return {'anchor':anchor,'choices':winners.map((w)=>{'type':'local','feature':places.get(w.id,language)!}).toList()};
  }
  void close()=>sql.close();
}
