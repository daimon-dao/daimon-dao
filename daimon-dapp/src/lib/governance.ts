import { encodeAbiParameters, keccak256, parseAbiParameters, zeroHash } from "viem";

/*
 * Fasi di una proposta (DAPP_SPEC.md §7).
 *
 * Tuple del getter pubblico `proposals(id)` di DaimonGovernor:
 *  0 proposer, 1 target, 2 value, 3 data, 4 description,
 *  5 snapshotTimestamp, 6 snapshotTotalVotingPower, 7 voteStart, 8 voteEnd,
 *  9 forVotes, 10 againstVotes, 11 abstainVotes,
 *  12 canceled, 13 executed, 14 queued, 15 timelockSalt
 */
export type ProposalTuple = readonly [
  `0x${string}`, // proposer
  `0x${string}`, // target
  bigint, // value
  `0x${string}`, // data
  string, // description
  bigint, // snapshotTimestamp
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
];

export type PhaseKey =
  | "pending"
  | "active"
  | "defeated"
  | "succeeded"
  | "timelock"
  | "ready"
  | "executed"
  | "canceled";

/*
 * Le etichette sono CHIAVI i18n (messages/{en,it}.json): i componenti le
 * risolvono con t() nella lingua attiva.
 */
export const PROPOSAL_PHASE: Record<
  PhaseKey,
  { labelKey: string; badgeClass: string }
> = {
  pending: { labelKey: "governance.phase.pending", badgeClass: "bg-secondario/20 text-secondario" },
  active: { labelKey: "governance.phase.active", badgeClass: "bg-oro/20 text-oro" },
  defeated: { labelKey: "governance.phase.defeated", badgeClass: "bg-rosso/20 text-rosso" },
  succeeded: { labelKey: "governance.phase.succeeded", badgeClass: "bg-verde/20 text-verde" },
  timelock: { labelKey: "governance.phase.timelock", badgeClass: "bg-oro/20 text-oro" },
  ready: { labelKey: "governance.phase.ready", badgeClass: "bg-verde/20 text-verde" },
  executed: { labelKey: "governance.phase.executed", badgeClass: "bg-verde/20 text-verde" },
  canceled: { labelKey: "governance.phase.canceled", badgeClass: "bg-secondario/20 text-secondario" },
};

export function phaseOf(
  state: number | undefined,
  p: ProposalTuple,
  now: number,
  timelockReadyTs?: bigint
): { key: PhaseKey; countdownTo?: number; countdownLabelKey?: string } {
  switch (state) {
    case 6:
      return { key: "canceled" };
    case 5:
      return { key: "executed" };
    case 0:
      return {
        key: "pending",
        countdownTo: Number(p[7]),
        countdownLabelKey: "governance.countdown.opensIn",
      };
    case 1:
      return {
        key: "active",
        countdownTo: Number(p[8]),
        countdownLabelKey: "governance.countdown.endsIn",
      };
    case 2:
      return { key: "defeated" };
    case 3: {
      if (!p[14]) return { key: "succeeded" };
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
      return { key: "pending" };
  }
}

/** Id dell'operazione nel timelock (hashOperation con predecessor 0). */
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
