/// Editable, reusable route metadata. A trail may remember the ride it was
/// derived from, but owns a separate point copy so edits never mutate raw ride
/// evidence.
class Trail {
  final int? id;
  final int? sourceTripId;
  final String name;
  final String description;
  final String surface;
  final String difficulty;
  final String direction;
  final String visibility;
  final int createdAt;
  final int updatedAt;
  final double distanceM;
  final int pointCount;
  final int segmentCount;

  const Trail({
    this.id,
    this.sourceTripId,
    required this.name,
    this.description = '',
    this.surface = 'unknown',
    this.difficulty = 'unknown',
    this.direction = 'both',
    this.visibility = 'private',
    required this.createdAt,
    required this.updatedAt,
    required this.distanceM,
    required this.pointCount,
    required this.segmentCount,
  });

  factory Trail.fromMap(Map<String, Object?> map) => Trail(
    id: map['id'] as int?,
    sourceTripId: map['sourceTripId'] as int?,
    name: map['name'] as String,
    description: map['description'] as String? ?? '',
    surface: map['surface'] as String? ?? 'unknown',
    difficulty: map['difficulty'] as String? ?? 'unknown',
    direction: map['direction'] as String? ?? 'both',
    visibility: map['visibility'] as String? ?? 'private',
    createdAt: map['createdAt'] as int,
    updatedAt: map['updatedAt'] as int,
    distanceM: (map['distanceM'] as num).toDouble(),
    pointCount: map['pointCount'] as int,
    segmentCount: map['segmentCount'] as int,
  );

  Map<String, Object?> toMap({bool includeId = true}) => {
    if (includeId && id != null) 'id': id,
    'sourceTripId': sourceTripId,
    'name': name,
    'description': description,
    'surface': surface,
    'difficulty': difficulty,
    'direction': direction,
    'visibility': visibility,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'distanceM': distanceM,
    'pointCount': pointCount,
    'segmentCount': segmentCount,
  };

  Trail copyWith({
    String? name,
    String? description,
    String? surface,
    String? difficulty,
    String? direction,
    String? visibility,
    int? updatedAt,
  }) => Trail(
    id: id,
    sourceTripId: sourceTripId,
    name: name ?? this.name,
    description: description ?? this.description,
    surface: surface ?? this.surface,
    difficulty: difficulty ?? this.difficulty,
    direction: direction ?? this.direction,
    visibility: visibility ?? this.visibility,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    distanceM: distanceM,
    pointCount: pointCount,
    segmentCount: segmentCount,
  );
}

class TrailPoint {
  final int? id;
  final int trailId;
  final int sequence;
  final int segment;
  final double latitude;
  final double longitude;
  final double altitudeM;

  const TrailPoint({
    this.id,
    required this.trailId,
    required this.sequence,
    required this.segment,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
  });

  factory TrailPoint.fromMap(Map<String, Object?> map) => TrailPoint(
    id: map['id'] as int?,
    trailId: map['trailId'] as int,
    sequence: map['sequence'] as int,
    segment: map['segment'] as int,
    latitude: (map['lat'] as num).toDouble(),
    longitude: (map['lng'] as num).toDouble(),
    altitudeM: (map['altitudeM'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toMap({bool includeId = true}) => {
    if (includeId && id != null) 'id': id,
    'trailId': trailId,
    'sequence': sequence,
    'segment': segment,
    'lat': latitude,
    'lng': longitude,
    'altitudeM': altitudeM,
  };
}

/// A rider-owned map marker. Waypoints may stand alone, relate to a curated
/// trail, or retain provenance to a ride without being owned by that ride.
class Waypoint {
  final int? id;
  final int? trailId;
  final int? sourceTripId;
  final String name;
  final String type;
  final String notes;
  final double latitude;
  final double longitude;
  final int createdAt;
  final int updatedAt;

  const Waypoint({
    this.id,
    this.trailId,
    this.sourceTripId,
    required this.name,
    this.type = 'note',
    this.notes = '',
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Waypoint.fromMap(Map<String, Object?> map) => Waypoint(
    id: map['id'] as int?,
    trailId: map['trailId'] as int?,
    sourceTripId: map['sourceTripId'] as int?,
    name: map['name'] as String,
    type: map['type'] as String? ?? 'note',
    notes: map['notes'] as String? ?? '',
    latitude: (map['lat'] as num).toDouble(),
    longitude: (map['lng'] as num).toDouble(),
    createdAt: map['createdAt'] as int,
    updatedAt: map['updatedAt'] as int,
  );

  Map<String, Object?> toMap({bool includeId = true}) => {
    if (includeId && id != null) 'id': id,
    'trailId': trailId,
    'sourceTripId': sourceTripId,
    'name': name,
    'type': type,
    'notes': notes,
    'lat': latitude,
    'lng': longitude,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
