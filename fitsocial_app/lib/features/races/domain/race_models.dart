/// The running calendar: South African race events, and how they get filtered.
///
/// The shape here follows what a runner actually asks when looking for a race —
/// when, where, how far, and does it count as a qualifier — rather than what a
/// race entry system stores. That is why [DistanceBucket] exists as a coarse
/// band alongside the exact kilometres on each [RaceDistance]: nobody searches
/// for a 21.0975 km event, they search for "a half".
library;

/// A South African province, plus the neighbouring countries the SA racing
/// calendar routinely includes.
///
/// Stored as short codes so a display-name rewrite never orphans a document.
/// The foreign entries sit in the same enum rather than a separate country
/// field because they are used the same way — as one geographic filter — and a
/// runner in Nelspruit treats a race in Maputo as just another option.
enum Province {
  easternCape('EC', 'Eastern Cape'),
  freeState('FS', 'Free State'),
  gauteng('GP', 'Gauteng'),
  kwazuluNatal('KZN', 'KwaZulu-Natal'),
  limpopo('LP', 'Limpopo'),
  mpumalanga('MP', 'Mpumalanga'),
  northWest('NW', 'North West'),
  northernCape('NC', 'Northern Cape'),
  westernCape('WC', 'Western Cape'),
  lesotho('LS', 'Lesotho'),
  namibia('NA', 'Namibia'),
  botswana('BW', 'Botswana'),
  mozambique('MZ', 'Mozambique'),
  eswatini('SZ', 'eSwatini'),
  zimbabwe('ZW', 'Zimbabwe');

  const Province(this.code, this.label);

  /// The stored value. Short on purpose — it is written on every event document
  /// and read on every filtered query.
  final String code;

  /// What the filter chip shows.
  final String label;

  /// Whether this is one of the nine SA provinces rather than a neighbour.
  ///
  /// The province filter leads with these: the calendar is a South African one,
  /// and burying Gauteng below Botswana to keep the list alphabetical would be
  /// tidy and useless.
  bool get isSouthAfrican => index <= Province.westernCape.index;

  static Province? byCode(String? code) {
    if (code == null) return null;
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }

  /// The nine SA provinces, in the order the filter shows them.
  static List<Province> get southAfrican => values
      .where((province) => province.isSouthAfrican)
      .toList(growable: false);
}

/// The distance bands the filter offers.
///
/// A coarse band rather than the exact kilometres, because the exact figure is
/// not what anybody filters on and because it lets one query answer "show me
/// halfs" across events that call the same distance 21 km, 21.1 km and
/// "Half Marathon". Each event carries its matching bands in a denormalised
/// array so a single `array-contains-any` covers the whole chip row.
enum DistanceBucket {
  fun('fun', 'Fun run', 'Under 5 km'),
  fiveK('5k', '5 km', '5 km'),
  tenK('10k', '10 km', '10 km'),
  fifteenK('15k', '15 km', '15 km'),
  half('21.1k', 'Half', '21.1 km'),
  thirtyK('30k', '30 km', '30 km'),
  marathon('42.2k', 'Marathon', '42.2 km'),
  ultra('ultra', 'Ultra', 'Over 42.2 km');

  const DistanceBucket(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static DistanceBucket? byKey(String? key) {
    if (key == null) return null;
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }

  /// Which band a distance in kilometres falls into.
  ///
  /// The boundaries are deliberately generous. A 21.4 km "half" and a 9.8 km
  /// "10 km" are both real races that really advertise themselves that way, and
  /// a runner who filters for a half and does not see one because the route was
  /// measured honestly has been failed by the filter, not served by it.
  static DistanceBucket forKilometres(double km) {
    if (km < 4) return fun;
    if (km < 7.5) return fiveK;
    if (km < 12.5) return tenK;
    if (km < 18) return fifteenK;
    if (km < 25) return half;
    if (km < 36) return thirtyK;
    if (km <= 45) return marathon;
    return ultra;
  }
}

/// A label on an event beyond its distance and place.
///
/// Two of these matter more than the rest and are the reason this is a first
/// class field rather than free text: [comradesQualifier] and
/// [twoOceansQualifier]. Between about September and April a large share of SA
/// road runners are choosing races by exactly one criterion — whether the time
/// will register for Comrades — and a calendar that cannot answer that is not
/// a South African running calendar.
enum RaceTag {
  road('road', 'Road'),
  trail('trail', 'Trail'),
  crossCountry('xc', 'Cross country'),
  comradesQualifier('comrades-qualifier', 'Comrades qualifier'),
  twoOceansQualifier('two-oceans-qualifier', 'Two Oceans qualifier'),
  nightRace('night', 'Night race'),
  womensRace('womens', "Women's race"),
  charity('charity', 'Charity'),
  stageRace('stage', 'Stage race'),
  virtual('virtual', 'Virtual');

  const RaceTag(this.key, this.label);

  final String key;
  final String label;

  static RaceTag? byKey(String? key) {
    if (key == null) return null;
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// Whether an event is still going ahead.
///
/// [cancelled] and [postponed] events stay in the collection rather than being
/// deleted. A runner who has the race in their calendar needs to find out it is
/// off, and an event that simply vanished tells them nothing.
enum RaceStatus {
  scheduled('scheduled'),
  entriesClosed('entries_closed'),
  soldOut('sold_out'),
  postponed('postponed'),
  cancelled('cancelled');

  const RaceStatus(this.key);

  final String key;

  static RaceStatus byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return RaceStatus.scheduled;
  }

  /// Whether entries can still be taken.
  bool get isOpen => this == scheduled;

  /// Whether the listing needs a banner explaining itself.
  bool get needsNotice => this != scheduled;

  String get label => switch (this) {
        scheduled => 'Entries open',
        entriesClosed => 'Entries closed',
        soldOut => 'Sold out',
        postponed => 'Postponed',
        cancelled => 'Cancelled',
      };
}

/// Where a listing came from, and whether a human has checked it.
///
/// Provenance is stored because the calendar mixes sources with genuinely
/// different reliability: a fixture transcribed from a provincial list is
/// firmer than one a user typed in from memory. [verifiedAt] is what the detail
/// screen shows, for the same reason the site we are matching shows it — a date
/// on a race is only worth as much as the last time somebody confirmed it.
enum RaceSource {
  /// Transcribed from an official fixture list or an entry platform.
  curated('curated'),

  /// Submitted through the app by a user or an organiser.
  submission('submission'),

  /// Arrived through a feed from an entry platform.
  partner('partner');

  const RaceSource(this.key);

  final String key;

  static RaceSource byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return RaceSource.curated;
  }
}

/// One distance option within an event.
class RaceDistance {
  const RaceDistance({
    required this.kilometres,
    required this.label,
    this.priceCents,
    this.startTime,
  });

  final double kilometres;

  /// What the organiser calls it — "Half Marathon", "10 km Fun Run".
  ///
  /// Kept as the organiser's own wording rather than derived from the distance,
  /// so a listing reads the way the race's own entry page reads.
  final String label;

  /// Entry fee in cents, or null when the organiser has not published one.
  ///
  /// Cents rather than rands because these are money and doubles are not. Null
  /// is meaningfully different from zero: a free fun run and a race whose fee
  /// has not been announced need to display differently.
  final int? priceCents;

  /// Local start time as `HH:mm`, when this distance starts later than the
  /// event's first start. Null means it goes with the gun.
  final String? startTime;

  DistanceBucket get bucket => DistanceBucket.forKilometres(kilometres);

  /// The fee as a rand string, or null when there is no published fee.
  String? get priceLabel {
    final cents = priceCents;
    if (cents == null) return null;
    if (cents == 0) return 'Free';
    // Whole rands are the norm for entry fees, so a trailing ",00" is noise.
    if (cents % 100 == 0) return 'R${cents ~/ 100}';
    return 'R${(cents / 100).toStringAsFixed(2)}';
  }
}

/// Where a race starts from.
class RaceVenue {
  const RaceVenue({
    required this.city,
    required this.province,
    this.name,
    this.addressLine,
    this.latitude,
    this.longitude,
  });

  /// The venue's own name — "Kyalami Corner", "Green Point Athletics Track".
  final String? name;

  final String? addressLine;
  final String city;
  final Province province;

  /// Start coordinates, when known.
  ///
  /// Optional because a fixture list gives a town and nothing more, and an
  /// event with no pin is still worth listing. What they drive today is the
  /// detail screen's "open in maps" link, which is simply absent without them.
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// The one-line place, as the list row shows it.
  String get shortLabel => '$city, ${province.label}';

  /// The fuller place, for the detail screen.
  String get longLabel {
    final venueName = name;
    if (venueName == null || venueName.isEmpty) return shortLabel;
    return '$venueName · $shortLabel';
  }
}

/// A race on the calendar.
class RaceEvent {
  const RaceEvent({
    required this.id,
    required this.name,
    required this.startAt,
    required this.venue,
    required this.distances,
    this.endAt,
    this.organiser,
    this.description,
    this.tags = const {},
    this.entryUrl,
    this.entryPlatform,
    this.imageUrl,
    this.status = RaceStatus.scheduled,
    this.source = RaceSource.curated,
    this.verifiedAt,
  });

  final String id;
  final String name;

  /// First start, in UTC.
  ///
  /// Stored as an instant rather than a local date because Firestore range
  /// queries need one, and rendered back through the device's zone. SA has no
  /// daylight saving, so the round trip is lossless in practice for every
  /// event on this calendar.
  final DateTime startAt;

  /// Last day of a multi-day event. Null for the single-day majority.
  final DateTime? endAt;

  final RaceVenue venue;

  /// Distance options, shortest first.
  final List<RaceDistance> distances;

  final String? organiser;
  final String? description;
  final Set<RaceTag> tags;

  /// Where to enter. Null when entries are on the day only, which is common for
  /// club league races.
  final String? entryUrl;

  /// Which entry system [entryUrl] points at — used for the button's wording
  /// and, later, for attributing an affiliate click.
  final String? entryPlatform;

  final String? imageUrl;
  final RaceStatus status;
  final RaceSource source;

  /// When a human last confirmed the details.
  final DateTime? verifiedAt;

  bool get isMultiDay => endAt != null;

  /// The distance bands this event covers.
  Set<DistanceBucket> get buckets =>
      distances.map((distance) => distance.bucket).toSet();

  /// The cheapest published fee across the distances, in cents.
  ///
  /// Null when no distance has a fee, which reads as "fee not published"
  /// rather than as free.
  int? get priceFromCents {
    int? lowest;
    for (final distance in distances) {
      final price = distance.priceCents;
      if (price == null) continue;
      if (lowest == null || price < lowest) lowest = price;
    }
    return lowest;
  }

  /// The "from R___" line on the list row.
  String? get priceFromLabel {
    final cents = priceFromCents;
    if (cents == null) return null;
    if (cents == 0) return 'Free';
    final single = distances.length == 1;
    final amount = cents % 100 == 0
        ? 'R${cents ~/ 100}'
        : 'R${(cents / 100).toStringAsFixed(2)}';
    return single ? amount : 'from $amount';
  }

  bool get isComradesQualifier => tags.contains(RaceTag.comradesQualifier);

  bool get isTwoOceansQualifier => tags.contains(RaceTag.twoOceansQualifier);

  bool get isTrail => tags.contains(RaceTag.trail);

  /// Whether the event has already happened, as of [now].
  ///
  /// Uses [endAt] when there is one so a three-day stage race does not read as
  /// past on its second morning.
  bool isPast(DateTime now) => (endAt ?? startAt).isBefore(now);

  /// Whole days until the start, from [now]. Negative once it is past.
  ///
  /// Counted in UTC, though both dates are local ones. Two local midnights
  /// with a clock change between them are not a whole number of 24-hour days
  /// apart, and `inDays` truncates the remainder -- which is a countdown
  /// reading a day short for half the year. What is being compared is the
  /// calendar fields, so projecting both onto UTC midnight is the exact form
  /// of the question.
  int daysUntil(DateTime now) {
    final start = DateTime.utc(startAt.year, startAt.month, startAt.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    return start.difference(today).inDays;
  }
}

/// The stretch of calendar being shown.
enum RaceTimeframe {
  thisWeek('week', 'This week'),
  thisMonth('month', 'This month'),
  threeMonths('3m', 'Next 3 months'),
  sixMonths('6m', 'Next 6 months'),
  all('all', 'All upcoming');

  const RaceTimeframe(this.key, this.label);

  final String key;
  final String label;

  static RaceTimeframe byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return RaceTimeframe.threeMonths;
  }

  /// The end of the window, from [now]. Null for [all], which has no end.
  ///
  /// "This week" runs to Sunday night rather than seven days out, and "this
  /// month" to month end: somebody asking what is on this weekend means this
  /// weekend, not the next 168 hours.
  DateTime? endFrom(DateTime now) => switch (this) {
        // Built as a date rather than by adding days of elapsed time: a week
        // containing a clock change is not seven 24-hour days, and the window
        // would end on the Saturday night.
        thisWeek => DateTime(now.year, now.month, now.day + (8 - now.weekday)),
        thisMonth => DateTime(now.year, now.month + 1, 1),
        threeMonths => DateTime(now.year, now.month + 3, now.day),
        sixMonths => DateTime(now.year, now.month + 6, now.day),
        all => null,
      };
}

/// A set of filters over the calendar.
///
/// Immutable, and the single argument to the repository's query. Bundling them
/// means the provider can key its cache on one value and the screen can reset
/// the whole row with one assignment.
class RaceFilter {
  const RaceFilter({
    this.timeframe = RaceTimeframe.threeMonths,
    this.provinces = const {},
    this.buckets = const {},
    this.tags = const {},
    this.query = '',
  });

  final RaceTimeframe timeframe;

  /// Empty means everywhere.
  final Set<Province> provinces;

  /// Empty means any distance.
  final Set<DistanceBucket> buckets;

  /// Tags an event must carry — this is how the qualifier chips work.
  final Set<RaceTag> tags;

  /// Free text over the name, organiser and city. Applied on the client: the
  /// result set for a timeframe is small enough that a substring match beats
  /// standing up a search index for it.
  final String query;

  bool get hasActiveFilters =>
      provinces.isNotEmpty ||
      buckets.isNotEmpty ||
      tags.isNotEmpty ||
      query.isNotEmpty ||
      timeframe != RaceTimeframe.threeMonths;

  RaceFilter copyWith({
    RaceTimeframe? timeframe,
    Set<Province>? provinces,
    Set<DistanceBucket>? buckets,
    Set<RaceTag>? tags,
    String? query,
  }) {
    return RaceFilter(
      timeframe: timeframe ?? this.timeframe,
      provinces: provinces ?? this.provinces,
      buckets: buckets ?? this.buckets,
      tags: tags ?? this.tags,
      query: query ?? this.query,
    );
  }

  /// Adds or removes one province.
  RaceFilter toggleProvince(Province province) => copyWith(
        provinces: _toggled(provinces, province),
      );

  RaceFilter toggleBucket(DistanceBucket bucket) => copyWith(
        buckets: _toggled(buckets, bucket),
      );

  RaceFilter toggleTag(RaceTag tag) => copyWith(tags: _toggled(tags, tag));

  /// Whether [event] passes the parts of the filter Firestore did not.
  ///
  /// Firestore can only carry one array-membership clause per query, so a
  /// filter naming both distances and tags has to finish on the client. This
  /// method is that finish, and it also runs the free-text match. It is
  /// deliberately the single place both concerns live so the list and the tests
  /// agree on what "matches" means.
  bool matches(RaceEvent event) {
    if (provinces.isNotEmpty && !provinces.contains(event.venue.province)) {
      return false;
    }
    if (buckets.isNotEmpty && buckets.intersection(event.buckets).isEmpty) {
      return false;
    }
    // Tags are an AND: picking "trail" and "Comrades qualifier" together asks
    // for a race that is both, which is the reading that makes the two
    // qualifier chips useful next to the terrain ones.
    if (tags.isNotEmpty && !tags.every(event.tags.contains)) return false;

    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return event.name.toLowerCase().contains(needle) ||
        event.venue.city.toLowerCase().contains(needle) ||
        // The venue is searched as well as the town, and that earns its keep on
        // renamed cities: Gqeberha's races are listed under the new name while
        // their venue addresses still read "Port Elizabeth", and a runner who
        // searches the name they grew up with should still find them.
        (event.venue.name?.toLowerCase().contains(needle) ?? false) ||
        (event.venue.addressLine?.toLowerCase().contains(needle) ?? false) ||
        (event.organiser?.toLowerCase().contains(needle) ?? false);
  }

  static Set<T> _toggled<T>(Set<T> current, T value) {
    final next = current.toSet();
    if (!next.remove(value)) next.add(value);
    return next;
  }

  @override
  bool operator ==(Object other) {
    return other is RaceFilter &&
        other.timeframe == timeframe &&
        other.query == query &&
        _setEquals(other.provinces, provinces) &&
        _setEquals(other.buckets, buckets) &&
        _setEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(
        timeframe,
        query,
        Object.hashAllUnordered(provinces),
        Object.hashAllUnordered(buckets),
        Object.hashAllUnordered(tags),
      );
}

/// A race somebody has submitted through the app, awaiting moderation.
///
/// A separate type from [RaceEvent] rather than an unpublished one, because a
/// submission is a claim and an event is a fact. Keeping them apart is what
/// lets the rules allow anyone to write the first and nobody to write the
/// second.
class RaceSubmission {
  const RaceSubmission({
    required this.name,
    required this.startAt,
    required this.city,
    required this.province,
    this.organiser,
    this.entryUrl,
    this.distancesNote,
    this.notes,
  });

  final String name;
  final DateTime startAt;
  final String city;
  final Province province;
  final String? organiser;
  final String? entryUrl;

  /// The distances as free text — "5, 10 and 21.1 km".
  ///
  /// Free text on purpose. A submission form that makes somebody build
  /// structured distance rows before they can tell us a race exists collects
  /// fewer races, and a moderator has to read the thing anyway.
  final String? distancesNote;

  final String? notes;
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
