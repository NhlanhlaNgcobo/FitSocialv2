import 'package:cloud_functions/cloud_functions.dart';

/// Where this app's Cloud Functions run.
///
/// Johannesburg, beside the Firestore database. That placement is forced rather
/// than chosen: second-generation Firestore triggers must run in the region of
/// the database they listen to, and this project's Firestore is in
/// africa-south1. The callables were only ever in us-central1 because that is
/// what the Firebase tooling defaults to when nothing says otherwise.
///
/// This constant has to agree with `setGlobalOptions` in functions/index.js.
/// The region is part of the URL a callable is invoked at, so a mismatch is not
/// a slow path or a warning — every call returns NOT_FOUND. Change one and you
/// must change the other in the same commit.
const String functionsRegion = 'africa-south1';

/// The Cloud Functions client, pointed at the region the functions are in.
///
/// Always use this rather than `FirebaseFunctions.instance`, which silently
/// targets us-central1 and will look fine in code review right up until it
/// 404s on a device.
FirebaseFunctions get appFunctions =>
    FirebaseFunctions.instanceFor(region: functionsRegion);
