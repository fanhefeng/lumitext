//
//  SaveOutcomeGate.swift
//  LumitextCore
//
//  Monotone sequencing for asynchronous save outcomes. The host hands each
//  write a sequence number; outcome reports can in principle reach the main
//  actor out of order (actor job ordering across independently created Tasks
//  isn't formally guaranteed), so stale reports must be dropped — the UI's
//  persistence warning must always reflect the LATEST write, never an older
//  one that happened to report last. Extracted from the app target so the
//  ordering contract has direct unit coverage.
//

/// Issue with `nextSequence()` when a write is enqueued; check with `admit(_:)`
/// when its outcome arrives. `admit` returns true exactly once per sequence and
/// only when no newer outcome has been admitted first.
public struct SaveOutcomeGate: Sendable {
    private var nextSeq = 0
    private var lastAdmitted = 0

    public init() {}

    /// The sequence number for a write about to be enqueued (strictly increasing).
    public mutating func nextSequence() -> Int {
        nextSeq += 1
        return nextSeq
    }

    /// True if this outcome is newer than every outcome admitted so far —
    /// the caller should apply it. False means a newer write already reported;
    /// the caller must drop this stale outcome.
    public mutating func admit(_ seq: Int) -> Bool {
        guard seq > lastAdmitted else { return false }
        lastAdmitted = seq
        return true
    }
}
