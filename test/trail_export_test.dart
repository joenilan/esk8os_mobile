import 'dart:convert';

import 'package:esk8os_mobile/models/trail.dart';
import 'package:esk8os_mobile/services/trail_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const trail = Trail(
    id: 7,
    sourceTripId: 3,
    name: 'Creek & Ridge <Loop>',
    description: 'Private "test" route',
    surface: 'mixed',
    difficulty: 'moderate',
    direction: 'loop',
    visibility: 'private',
    createdAt: 1,
    updatedAt: 2,
    distanceM: 42,
    pointCount: 4,
    segmentCount: 2,
  );
  const points = [
    TrailPoint(
      trailId: 7,
      sequence: 0,
      segment: 0,
      latitude: 40,
      longitude: -75,
      altitudeM: 100,
    ),
    TrailPoint(
      trailId: 7,
      sequence: 1,
      segment: 0,
      latitude: 40.0001,
      longitude: -75,
      altitudeM: 101,
    ),
    TrailPoint(
      trailId: 7,
      sequence: 2,
      segment: 1,
      latitude: 40.01,
      longitude: -75,
      altitudeM: 110,
    ),
    TrailPoint(
      trailId: 7,
      sequence: 3,
      segment: 1,
      latitude: 40.0101,
      longitude: -75,
      altitudeM: 111,
    ),
  ];
  const waypoints = [
    Waypoint(
      id: 9,
      trailId: 7,
      name: 'Water & tools',
      type: 'water',
      notes: 'Creek <crossing>',
      latitude: 40.0001,
      longitude: -75,
      createdAt: 1,
      updatedAt: 1,
    ),
  ];

  test('GPX preserves segment breaks and escapes rider text', () {
    final gpx = TrailExport.buildGpx(trail, points, waypoints);

    expect('<trkseg>'.allMatches(gpx), hasLength(2));
    expect(gpx, contains('Creek &amp; Ridge &lt;Loop&gt;'));
    expect(gpx, contains('Water &amp; tools'));
    expect(gpx, contains('Creek &lt;crossing&gt;'));
    expect(gpx, isNot(contains('Creek & Ridge <Loop>')));
  });

  test('GeoJSON emits MultiLineString plus typed waypoint features', () {
    final data =
        jsonDecode(TrailExport.buildGeoJson(trail, points, waypoints))
            as Map<String, dynamic>;
    final features = data['features'] as List;
    final route = features.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;

    expect(data['type'], 'FeatureCollection');
    expect(geometry['type'], 'MultiLineString');
    expect(geometry['coordinates'], hasLength(2));
    expect((features.last as Map)['properties']['type'], 'water');
    expect((route['properties'] as Map)['sourceTripId'], 3);
  });
}
