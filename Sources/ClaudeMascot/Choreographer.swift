import Foundation

/// Chooses what plays next: walks the pose graph one edge at a time, rotates
/// weighted variants, and injects ambient fidgets on long holds.
///
/// Deliberately a **pure function of (target, displayed, now)**. `PanelController`
/// calls `clip(for:displayed:)` on every `tick()`, speculatively, just to compare
/// its answer against what is already showing — including ticks where nothing
/// changes. If this type remembered anything ("last variant played", "next
/// fidget due at"), that bookkeeping would advance on every speculative call,
/// not just the calls that actually led to an upload, and the same instant
/// asked twice would give two different answers. So nothing is stored:
///
/// - **Selection is derived from time, not remembered.** An epoch
///   (`Int(now / rotationPeriod)`) seeds a deterministic RNG together with a
///   stable key (group name, purpose). Called twice in the same epoch with
///   the same inputs, it returns the same clip.
/// - **Current pose is derived from `displayed`, not stored.** See
///   `pose(of:)`.
/// - **Only one edge of the path is ever returned, never the whole route.**
///   If the caller comes back with a different target before the edge lands,
///   the next call simply computes a fresh path from wherever `displayed`
///   says the mascot now is. There is no plan to unwind or cancel — this is
///   what makes a mid-journey flip self-correcting instead of a bug to guard
///   against.
///
/// This also makes the type exhaustively testable against a fake clock: every
/// answer is reproducible from its three inputs alone.
@MainActor
final class Choreographer {
  private let manifest: ClipManifest
  private let clock: () -> TimeInterval
  private let rotationPeriod: TimeInterval
  private let fidgetChance: Double

  init(
    manifest: ClipManifest,
    clock: @escaping () -> TimeInterval,
    rotationPeriod: TimeInterval = 20,
    // 0.3 per rotation-period epoch is roughly one fidget onset a minute --
    // twice the old 0.15, because the seated `working` hold read as monotonous
    // at the sparser rate. Note a fired fidget holds the rest of its epoch (the
    // same clip is re-picked until the epoch rolls, and an unchanged clip is
    // never re-uploaded), so this is the share of held time that fidgets, not a
    // count of discrete beats.
    fidgetChance: Double = 0.3
  ) {
    self.manifest = manifest
    self.clock = clock
    self.rotationPeriod = rotationPeriod
    self.fidgetChance = fidgetChance
  }

  /// The clip that should be showing, given what the world wants and what is
  /// on the panel now. `nil` when nothing can be resolved (an empty
  /// manifest, or a state with no clip in its group yet) — `PanelController`
  /// treats that like a failed upload and retries, so this never has to
  /// throw or stall to signal "not yet possible".
  func clip(for target: PanelState, displayed: Clip?) -> Clip? {
    let now = clock()
    let currentPose = pose(of: displayed)

    // 1. The two journeys. Neither has a pose of its own (see
    // `PanelState.pose`), so each resolves its own ends here.
    switch target {
    case .starting:
      // The entrance is an *edge from off screen*, not a state. Asking for it
      // while the mascot is already standing there used to hand back
      // `transition(from: .standing, to: .standing)` — which matches every
      // self-edge in the manifest, so a `SessionStart` on a visible mascot
      // drew a fidget, and one time in nine a *wander*: the mascot walked off
      // the panel and strolled back in, for no reason the user could see.
      // Already on screen means the arrival has nothing to do.
      guard currentPose.isOffscreen else { break }
      return manifest.transition(from: currentPose, to: .standing)
    case .away:
      // The departure. Already gone is the terminal state, and
      // `PanelController` reads that off `displayed` itself rather than from
      // a clip here — there is nothing left to play.
      guard !currentPose.isOffscreen else { return nil }
      if let edge = nextEdge(from: currentPose, to: exitPose(now: now)) {
        return edge
      }
      // No way off the panel from here (missing art). Reporting nothing is
      // right: `PanelController` cuts power rather than stranding the mascot
      // mid-walk or retrying an edge that does not exist.
      return nil
    default:
      break
    }

    guard let targetPose = target.pose else {
      // `.starting` on a mascot that is already standing: fall through to the
      // pose it was arriving at anyway, so the entrance settles into idle
      // instead of resolving to nothing.
      return clip(for: .idle, displayed: displayed)
    }

    // 2. Not there yet: take the next step, not the whole trip. `nextEdge`
    // recomputes from `currentPose` every time, so a target that flips
    // mid-walk is handled for free — there is no stale plan to notice and
    // cancel, just a new shortest path from wherever `displayed` now says we
    // are.
    if currentPose != targetPose {
      if let edge = nextEdge(from: currentPose, to: targetPose) {
        return edge
      }
      // Graceful degradation: the art for this route does not exist yet
      // (true of nearly every route today — only `starting` ships as a
      // transition). Rather than stall forever waiting for edges that may
      // never come, swap directly to the target's loop at the next boundary.
      return selectVariant(group: target.rawValue, displayed: displayed, now: now)
    }

    let group = target.rawValue

    // 3. Just arrived: play the one-shot entrance if the manifest has one.
    // "Just arrived" means displayed is either a loop clip from some *other*
    // group (a graceless direct swap landed here without walking an edge)
    // or a real transition (fromPose != toPose — the edge that walked us
    // here). It deliberately excludes the two other kinds of non-looping
    // clip that can be on screen at this pose: the enter clip itself, once
    // it has already played, and a fidget — both are self-edges
    // (fromPose == toPose == this pose) and neither should be mistaken for
    // a fresh arrival, or the entrance would replay forever and a fidget
    // would look like a re-entrance. `done-enter` is the celebration chunk 9
    // authors; most groups have none yet, so this falls through cleanly.
    let justArrived =
      displayed.map { $0.variantGroup != nil ? $0.variantGroup != group : isRealTransition($0) }
      ?? true
    if justArrived {
      if let enterClip = manifest["\(group)-enter"], !enterClip.loops {
        return enterClip
      }
    }

    // 4. Settled and idle a while: maybe a fidget. Never while a real
    // transition is still the thing on screen (it only just arrived — let
    // the entrance/variant settle first), and never for `.off`, which has
    // no body on the panel to move.
    if target != .off, let displayed, !isRealTransition(displayed) {
      if fidgetDue(group: group, now: now),
        let fidget = selectFidget(group: group, pose: targetPose, now: now)
      {
        return fidget
      }
    }

    // 5. Otherwise: the target's rotating variant.
    return selectVariant(group: group, displayed: displayed, now: now)
  }

  /// Where the mascot is, derived from `displayed` rather than tracked
  /// separately — a second source of truth for "where is it" would drift
  /// from the first the moment an upload is deferred to a boundary.
  ///
  /// - a looping clip is showing: its `pose`
  /// - a non-looping clip is showing (transition, fidget, or one-shot
  ///   entrance): its `toPose` — by the time we are asked again, whatever it
  ///   was doing has arrived (transitions hand off at `motion`, not
  ///   `duration`; see `PanelController.nextBoundary`)
  /// - nothing is showing: `.offBottom` — the mascot is not on screen
  func pose(of displayed: Clip?) -> Pose {
    guard let displayed else { return .offBottom }
    if let pose = displayed.pose { return pose }
    return displayed.toPose ?? .offBottom
  }

  /// Which side the mascot leaves by, chosen per epoch like everything else
  /// here so the answer stays a pure function of time.
  ///
  /// Deliberately the two walks and not `sink`: sinking through the floor is
  /// the entrance played backwards, and reads as the mascot being swallowed
  /// rather than choosing to go. Walking off is the mascot leaving on its own
  /// terms, which is what the panel going dark should look like. `sink` keeps
  /// its place inside the wander fidgets, where the mascot comes back.
  private func exitPose(now: TimeInterval) -> Pose {
    var rng = SplitMix64(seed: seed(for: "exit-side", epoch: Int(now / rotationPeriod)))
    return rng.nextDouble() < 0.5 ? .offLeft : .offRight
  }

  // MARK: - Path finding

  /// The first edge of the shortest path from `start` to `goal`, or `nil`
  /// when no route exists in today's manifest. A breadth-first search over
  /// the (tiny, six-node) pose graph, tracking only the first edge taken out
  /// of `start` toward each frontier node — that first edge is the only part
  /// of the path this ever needs to hand back.
  private func nextEdge(from start: Pose, to goal: Pose) -> Clip? {
    guard start != goal else { return nil }

    var adjacency: [Pose: [(to: Pose, clip: Clip)]] = [:]
    for clip in manifest.clips.values where !clip.loops {
      guard let from = clip.fromPose, let to = clip.toPose else { continue }
      adjacency[from, default: []].append((to, clip))
    }

    var visited: Set<Pose> = [start]
    // Each queue entry is a frontier pose paired with the first edge taken
    // from `start` to reach it — that edge is what gets returned the moment
    // the frontier reaches `goal`.
    var queue: [(pose: Pose, firstEdge: Clip)] = []

    for (to, edge) in (adjacency[start] ?? []).sorted(by: { $0.clip.id < $1.clip.id }) {
      guard visited.insert(to).inserted else { continue }
      if to == goal { return edge }
      queue.append((to, edge))
    }

    var head = 0
    while head < queue.count {
      let (pose, firstEdge) = queue[head]
      head += 1
      for (to, _) in (adjacency[pose] ?? []).sorted(by: { $0.clip.id < $1.clip.id }) {
        guard visited.insert(to).inserted else { continue }
        if to == goal { return firstEdge }
        queue.append((to, firstEdge))
      }
    }
    return nil
  }

  private func isRealTransition(_ clip: Clip) -> Bool {
    guard !clip.loops, let from = clip.fromPose, let to = clip.toPose else { return false }
    return from != to
  }

  // MARK: - Variant selection

  /// The target's weighted-random loop clip for the current epoch, never
  /// repeating whatever is currently displayed (when there is something else
  /// to pick).
  ///
  /// "Previous pick" is read off `displayed` itself rather than
  /// recomputed from `(group, epoch - 1)` — `displayed` already *is* the
  /// last clip this group showed (that is what "no immediate repeat" means:
  /// don't repeat what's on screen), and treating it as the source avoids
  /// two problems a recomputation has. First, unbounded recursion: an
  /// epoch-1 pick would itself need epoch-2 excluded to be accurate, all
  /// the way back to epoch zero — infeasible against a real Unix-time clock
  /// with millions of epochs behind it. Second, and worse, self-defeat: a
  /// heavily weighted candidate is also the *likeliest raw pick for
  /// epoch - 1*, so excluding "whatever epoch - 1 would have drawn"
  /// disproportionately excludes exactly the candidate the weights are
  /// trying to favour, inverting the intended effect. Reading the real
  /// `displayed` clip has neither problem and is still a pure read of an
  /// input, not stored state.
  private func selectVariant(group: String, displayed: Clip?, now: TimeInterval) -> Clip? {
    let candidates = manifest.clips(inGroup: group)
    guard !candidates.isEmpty else { return nil }
    guard candidates.count > 1 else { return candidates[0] }

    let epoch = Int(now / rotationPeriod)
    let previousId = displayed?.variantGroup == group ? displayed?.id : nil
    let withoutPrevious = candidates.filter { $0.id != previousId }
    let pool = withoutPrevious.isEmpty ? candidates : withoutPrevious
    return weightedPick(seedKey: "variant:\(group)", epoch: epoch, candidates: pool)
  }

  // MARK: - Fidgets

  /// Whether this epoch's seeded roll lands under `fidgetChance`. A distinct
  /// seed key from variant selection so the two rolls do not correlate (a
  /// group that always rotates variants on an unlucky roll would never
  /// fidget, and vice versa).
  private func fidgetDue(group: String, now: TimeInterval) -> Bool {
    let epoch = Int(now / rotationPeriod)
    var rng = SplitMix64(seed: seed(for: "fidget-due:\(group)", epoch: epoch))
    return rng.nextDouble() < fidgetChance
  }

  /// A fidget clip at `pose` — a non-looping clip that starts and ends at
  /// the same pose, distinguishing it from a real transition (which moves
  /// between two different poses) and from the group's own one-shot
  /// entrance (excluded by id).
  ///
  /// A fidget with no `fidgetGroup` fits any state at this pose — that is what
  /// `fidget-stretch` and `fidget-look` are, small motion that suits standing
  /// whatever the mascot is standing there for. One that declares a group is
  /// kept to it: the wander fidgets walk the mascot off the panel entirely, which
  /// is charming during `idle` and alarming during `waiting`, where the whole
  /// point of the clip on screen is that Claude needs the user.
  private func selectFidget(group: String, pose: Pose, now: TimeInterval) -> Clip? {
    let candidates =
      manifest.clips.values
      .filter {
        !$0.loops && $0.fromPose == pose && $0.toPose == pose && $0.id != "\(group)-enter"
          && ($0.fidgetGroup == nil || $0.fidgetGroup == group)
      }
      .sorted { $0.id < $1.id }
    guard !candidates.isEmpty else { return nil }
    let epoch = Int(now / rotationPeriod)
    return weightedPick(seedKey: "fidget-pick:\(group)", epoch: epoch, candidates: candidates)
  }

  // MARK: - Weighted pick

  /// One weighted-random draw from `candidates`, seeded from `(seedKey,
  /// epoch)` so it is reproducible: the same key and epoch always draw the
  /// same clip, no matter how many times or in what order this is called.
  private func weightedPick(seedKey: String, epoch: Int, candidates: [Clip]) -> Clip? {
    guard !candidates.isEmpty else { return nil }
    let sorted = candidates.sorted { $0.id < $1.id }
    guard sorted.count > 1 else { return sorted[0] }

    var rng = SplitMix64(seed: seed(for: seedKey, epoch: epoch))
    let total = sorted.reduce(0.0) { $0 + $1.weight }
    guard total > 0 else { return sorted[0] }

    let threshold = rng.nextDouble() * total
    var cumulative = 0.0
    for clip in sorted {
      cumulative += clip.weight
      if threshold < cumulative { return clip }
    }
    return sorted.last
  }

  /// A deterministic 64-bit seed from a stable key and an epoch, so the same
  /// `(key, epoch)` always seeds the RNG identically across runs. Built from
  /// FNV-1a rather than `String.hashValue`, whose value is randomized per
  /// process launch and would make tests (and repeated app runs) see a
  /// different rotation order every time.
  private func seed(for key: String, epoch: Int) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in key.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    hash ^= UInt64(bitPattern: Int64(epoch))
    hash = hash &* 0x0000_0100_0000_01B3
    return hash
  }
}

/// A tiny, dependency-free, reproducible RNG (SplitMix64). Used instead of
/// `Int.random`/`.shuffle`, whose results are seeded from system entropy and
/// so cannot be reproduced in a test — everything here has to be derivable
/// from `(target, displayed, now)` alone.
private struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  private mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// A uniform double in `[0, 1)`.
  mutating func nextDouble() -> Double {
    Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)  // 2^53
  }
}
