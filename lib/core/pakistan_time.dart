// The timetable is in Pakistan time, and the server checks Pakistan time
// (Asia/Karachi). The app must use the same clock, even if the phone is set
// to another time zone.
//
// Pakistan Standard Time is always UTC+5 (no daylight saving), so we can
// calculate it without a time zone package.
//
// The returned DateTime's weekday / hour / minute are Pakistan's.
// Do not call .toLocal() on it.
DateTime pakistanNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 5));
