import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'core_failure.dart';
import 'local_state.dart';

/// Transactional handoff of the three R16 UI keys; auth and user content are
/// outside this repository's ownership and are never copied or removed.
final class R16Preferences {
  R16Preferences(this.state);
  final LocalState state;
  static const sessionKey='nav-kurd:app-session';
  static const tutorialKey='nav-kurd:tutorial:completed';
  static const trackingKey='nav-kurd:gps:active';
  static const legacyKeys=[sessionKey,tutorialKey,trackingKey];
  static const maxAgeMs=7*24*60*60*1000;
  static bool _number(Object? value)=>value is num&&value.isFinite;
  static bool _valid(Map value){
    final camera=value['camera'];
    if(camera is! Map)return false;
    final center=camera['center'];
    return value['schema']==1&&_number(value['savedAt'])&&
      center is List&&center.length==2&&center.every(_number)&&
      (center[0] as num)>=-180&&(center[0] as num)<=180&&(center[1] as num)>=-90&&(center[1] as num)<=90&&
      ['zoom','bearing','pitch'].every((k)=>_number(camera[k]))&&
      ['ku','ar','en'].contains(value['language'])&&['street','night','satellite'].contains(value['mapMode'])&&
      ['sheetCollapsed','basemapVisible','administrativeVisible','placesVisible','controlsHidden'].every((k)=>value[k] is bool);
  }
  static Map<String,Object?> _fields(Map snapshot)=>{
    'camera':snapshot['camera'],'language':snapshot['language'],'mapMode':snapshot['mapMode'],
    'layerVisibility':{for(final k in ['basemapVisible','administrativeVisible','placesVisible'])k:snapshot[k]},
    'controlVisibility':{'controlsHidden':snapshot['controlsHidden']},
    'lastNonSensitiveState':{for(final k in ['schema','savedAt','sheetCollapsed'])k:snapshot[k]},
  };
  void save(Map snapshot){
    if(!_valid(snapshot))throw const CoreFailure('invalid_snapshot','Invalid R16 UI state.');
    state.update(_fields(snapshot));
  }
  Map<String,Object?> read(){
    final fields=state.snapshot(),rest=fields['lastNonSensitiveState'];
    Map<String,Object?>? session;
    if(rest is Map&&fields['layerVisibility'] is Map&&fields['controlVisibility'] is Map){
      final value=<String,Object?>{...Map<String,Object?>.from(rest),...Map<String,Object?>.from(fields['layerVisibility'] as Map),...Map<String,Object?>.from(fields['controlVisibility'] as Map),
        'camera':fields['camera'],'language':fields['language'],'mapMode':fields['mapMode']};
      if(_valid(value)&&DateTime.now().millisecondsSinceEpoch-(value['savedAt'] as num)<=maxAgeMs)session=value;
    }
    return {'snapshot':session,'tutorialCompleted':fields['tutorialCompleted']==true,'trackingEnabled':fields['trackingEnabled']==true};
  }
  Map<String,Object?> importLegacy(Map<String,Object?> raw){
    if(raw.keys.any((k)=>!legacyKeys.contains(k))||raw.values.any((v)=>v!=null&&(v is! String||utf8.encode(v).length>65536))) {
      throw const CoreFailure('invalid_import','Only the three bounded R16 UI values may be imported.');
    }
    final ordered={for(final key in legacyKeys)key:raw[key]},values=<String,Object?>{};
    var discarded=false;
    final serialized=raw[sessionKey];
    if(serialized!=null){
      Object? parsed;
      try{parsed=jsonDecode(serialized as String);}on FormatException{discarded=true;}
      if(parsed is Map&&_valid(parsed)&&DateTime.now().millisecondsSinceEpoch-(parsed['savedAt'] as num)<=maxAgeMs){values.addAll(_fields(parsed));}
      else {discarded=true;}
    }
    if(raw[tutorialKey]!=null)values['tutorialCompleted']=raw[tutorialKey]=='1';
    if(raw[trackingKey]!=null)values['trackingEnabled']=raw[trackingKey]=='1';
    final hash=sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
    final receipt=state.importUi(values,hash);
    return {...read(),'receipt':receipt,'capturedSourceHash':hash,'invalidOrExpiredSessionDiscarded':discarded};
  }
}
