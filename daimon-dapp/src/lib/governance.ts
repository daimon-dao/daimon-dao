import { encodeAbiParameters, keccak256, parseAbiParameters, zeroHash } from "viem";

/*
 * Phases of a proposal (DAPP_SPEC.md §7).
 *
 * Tuple of DaimonGovernor's public getter `proposals(id)`:
 *  0 proposer, 1 target, 2 value, 3 data, 4 description,
 *  5 snapshotBlock (numero di BLOCCO, fix #12), 6 snapshotTotalVotingPower,
 *  7 voteStart, 8 voteEnd,
 *  9 forVotes, 10 againstVotes, 11 abstainVotes,
 *  12 canceled, 13 executed, 14 queued, 15 timelockSalt,
 *  16 quorumBpsSnapshot (bps catturati alla creazione, fix #37)
 */
export type ProposalTuple = readonly [
  `0x${string}`, // proposer
  `0x${string}`, // target
  bigint, // value
  `0x${string}`, // data
  string, // description
  bigint, // snapshotBlock
  bigint, // snapshotTotalVotingPower
  bigint, // voteStart
  bigint, // voteEnd
  bigint, // forVotes
  bigint, // againstVotes
  bigint, // abstainVotes
  boolean, // canceled
  boolean, // executed
  boolean, // queued
  `0x${string}`, // timelockSalt
  bigint, // quorumBpsSnapshot
];

export type PhaseKey =
  | "loading"
  | "pending"
  | "active"
  | "defeated"
  | "succeeded"
  | "timelock"
  | "ready"
  | "executed"
  | "canceled";

/*
 * The labels are i18n KEYS (messages/{en,it}.json): the components resolve
 * them with t() in the active language.
 */
export const PROPOSAL_PHASE: Record<
  PhaseKey,
  { labelKey: string; badgeClass: string }
> = {
  loading: { labelKey: "governance.phase.loading", badgeClass: "bg-secondario/10 text-secondario" },
  pending: { labelKey: "governance.phase.pending", badgeClass: "bg-secondario/20 text-secondario" },
  active: { labelKey: "governance.phase.active", badgeClass: "bg-oro/20 text-oro" },
  defeated: { labelKey: "governance.phase.defeated", badgeClass: "bg-rosso/20 text-rosso" },
  succeeded: { labelKey: "governance.phase.succeeded", badgeClass: "bg-verde/20 text-verde" },
  timelock: { labelKey: "governance.phase.timelock", badgeClass: "bg-oro/20 text-oro" },
  ready: { labelKey: "governance.phase.ready", badgeClass: "bg-verde/20 text-verde" },
  executed: { labelKey: "governance.phase.executed", badgeClass: "bg-verde/20 text-verde" },
  canceled: { labelKey: "governance.phase.canceled", badgeClass: "bg-secondario/20 text-secondario" },
};

/** DaimonGovernor.ProposalState, in declaration order. */
export const ProposalState = {
  Pending: 0,
  Active: 1,
  Defeated: 2,
  Succeeded: 3,
  Queued: 4,
  Executed: 5,
  Canceled: 6,
} as const;

/*
 * The status comes ONLY from Governor.state(id), never from the struct's
 * canceled/executed/queued flags: state() is the one place that also folds in
 * a cancellation made directly on the Timelock (it reports Canceled while the
 * struct still says queued). The struct supplies timing only (voteStart,
 * voteEnd for the countdowns); the Timelock's readyTimestamp splits Queued
 * into "in timelock" and "ready". state() not read yet -> "loading", never a
 * guessed phase.
 */
export function phaseOf(
  state: number | undefined,
  p: ProposalTuple,
  now: number,
  timelockReadyTs?: bigint
): { key: PhaseKey; countdownTo?: number; countdownLabelKey?: string } {
  switch (state) {
    case ProposalState.Canceled:
      return { key: "canceled" };
    case ProposalState.Executed:
      return { key: "executed" };
    case ProposalState.Pending:
      return {
        key: "pending",
        countdownTo: Number(p[7]),
        countdownLabelKey: "governance.countdown.opensIn",
      };
    case ProposalState.Active:
      return {
        key: "active",
        countdownTo: Number(p[8]),
        countdownLabelKey: "governance.countdown.endsIn",
      };
    case ProposalState.Defeated:
      return { key: "defeated" };
    case ProposalState.Succeeded:
      return { key: "succeeded" };
    case ProposalState.Queued: {
      const ready = timelockReadyTs !== undefined ? Number(timelockReadyTs) : undefined;
      if (ready !== undefined && ready > 0 && now < ready) {
        return {
          key: "timelock",
          countdownTo: ready,
          countdownLabelKey: "governance.countdown.executableIn",
        };
      }
      if (ready !== undefined && ready > 0) return { key: "ready" };
      return { key: "timelock" };
    }
    default:
      return { key: "loading" };
  }
}

/** Timelock operation id (hashOperation with predecessor 0). */
export function timelockOperationId(p: ProposalTuple): `0x${string}` {
  return keccak256(
    encodeAbiParameters(parseAbiParameters("address, uint256, bytes, bytes32, bytes32"), [
      p[1],
      p[2],
      p[3],
      zeroHash,
      p[15],
    ])
  );
}
