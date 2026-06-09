//
//  Identifiers.swift
//  LumitextCore
//
//  Shared identifier constants. Both the host app and the saver appex depend on
//  LumitextCore, so the bundle-id-derived strings they log under (and the IO
//  queue label) live here once instead of being hand-copied into every
//  Logger(subsystem:) call site.
//

public enum Identifiers {
    /// The unified os.log subsystem for every Lumitext process (host + saver).
    /// Matches the host bundle identifier; the saver shares it so a single
    /// `log` predicate captures both. (Build-system occurrences — project.yml,
    /// Info.plist, entitlements — are necessarily separate and not derivable
    /// from this constant.)
    public static let subsystem = "io.github.fanhefeng.lumitext"
}
