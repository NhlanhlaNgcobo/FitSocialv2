/// Whether music *accounts* are part of the product right now.
///
/// False, deliberately. FitSocial reads and drives whatever this phone is
/// already playing, through Android's media session: one system toggle, every
/// music app, free tiers included, no sign-in and no per-user gate of any kind.
/// That covers showing the track, play/pause, skip, seek and volume — the whole
/// feature as far as anyone using it is concerned.
///
/// The one thing it cannot do is *start* a chosen song. Android hands out a
/// controller for a session another app already opened; there is no call on it
/// that means "play this". Buying that ability back means an account, and on
/// Spotify it means their developer allowlist — a fixed handful of approved
/// users until the app passes extended-quota review. Trading a feature that
/// works for everyone against one that works for a couple of dozen people is
/// the wrong trade at this size.
///
/// Nothing behind this flag is deleted. The PKCE clients, the Spotify Web API,
/// the App Remote bridge, the library sheet and all of their tests still build
/// and still pass — this only decides whether any of it is reachable from the
/// UI. Setting it true is the whole of turning accounts back on.
const bool kMusicAccountsEnabled = false;
