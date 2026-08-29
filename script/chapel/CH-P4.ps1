# Day 2 -- P2.1b: the vote. Three ballots, one per support value, on the
# real clock. The plan named the voters (staker1/2/3) but not their
# directions; the choice here mirrors day 1's "three stakers, three lock
# tiers": three ballots, three support values, weights distinct enough
# (20 / 7.5 / 5 B) that the tally alone attributes every ballot. The
# outcome is unchanged -- forVotes 20B > againstVotes 7.5B, quorum
# (for+abstain) 25B >= 3.25B -- so the calendar (queue day 7, execute
# ~day 13-14) stands. Recorded, not hidden, as a choice the plan left open.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S

# Chain guard: this script must never speak to anything but Chapel.
$chainId = (cast chain-id --rpc-url $script:RPC)
if ("$chainId" -ne "97") { throw "WRONG CHAIN: chain-id=$chainId (expected 97) -- refusing to continue" }

# Restore the proposalId key (written by CH-P2a-recover at invariant check
# 24, lost from state.json by a later rewrite -- the chain is the source of
# truth: proposalCount is still 1, so the id is 0).
$propCount = CQ $st.governor "proposalCount()(uint256)"
if ($propCount -ne 1) { throw "UNEXPECTED proposalCount=$propCount (plan says exactly 1: the day-1 setFees proposal)" }
$propId = "0"
$stFix = S
$stFix | Add-Member -NotePropertyName proposalId -NotePropertyValue $propId -Force
Save-State $stFix

$PROP_SIG = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
function ReadProposal {
  $lines = @(cast call $st.governor $PROP_SIG $propId --rpc-url $script:RPC)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 17) { throw "proposals($propId) read failed" }
  $tok = @(); foreach ($l in $lines) { $tok += ($l.Trim() -split "\s+")[0] }
  return @{
    proposer = $tok[0]; target = $tok[1]; value = $tok[2]; data = $tok[3]
    description = $lines[4].Trim()
    snapshotBlock = [System.Numerics.BigInteger]::Parse($tok[5])
    snapTotal = [System.Numerics.BigInteger]::Parse($tok[6])
    voteStart = [System.Numerics.BigInteger]::Parse($tok[7])
    voteEnd = [System.Numerics.BigInteger]::Parse($tok[8])
    forVotes = [System.Numerics.BigInteger]::Parse($tok[9])
    againstVotes = [System.Numerics.BigInteger]::Parse($tok[10])
    abstainVotes = [System.Numerics.BigInteger]::Parse($tok[11])
    canceled = $tok[12]; executed = $tok[13]; queued = $tok[14]
    quorumBps = [System.Numerics.BigInteger]::Parse($tok[16])
  }
}
function UtcOf { param($unix) return [DateTimeOffset]::FromUnixTimeSeconds([int64]"$unix").UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") }

Log-Scenario "P2.1b" "Governance cycle, day 2: the vote -- three ballots, one per support value"

# --- P2.1b.1: window + integrity preflight, everything from live chain state
$p = ReadProposal
$now = [System.Numerics.BigInteger]::Parse((cast block latest -f timestamp --rpc-url $script:RPC))
$state0 = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$expectedCalldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$calldataOk = ($p.data.ToLower() -eq $expectedCalldata.ToLower())
$inWindow = ($now -ge $p.voteStart -and $now -le $p.voteEnd)
$tallyZero = ($p.forVotes -eq 0 -and $p.againstVotes -eq 0 -and $p.abstainVotes -eq 0)
$ok1 = ($chainId -eq "97" -and $state0 -eq "1" -and $inWindow -and $tallyZero -and $calldataOk -and $p.target.ToLower() -eq "$($st.token)".ToLower())
Log-Step "P2.1b.1" "Preflight from live state: chain, proposal $propId, window, calldata, virgin tally" "chain 97; state Active; now inside [voteStart,voteEnd]; data == setFees(10,10,20); tallies 0/0/0; target == token" "chain=$chainId, state=$state0 (1=Active), window $(UtcOf $p.voteStart) -> $(UtcOf $p.voteEnd) UTC (now $(UtcOf $now)), calldataMatch=$calldataOk, for/against/abstain=$($p.forVotes)/$($p.againstVotes)/$($p.abstainVotes), target=$($p.target)" "-" $(if ($ok1) { "PASS" } else { "DEVIATION" })
if (-not $ok1) { throw "preflight failed -- stopping before any ballot" }

$fromBlock = (cast block latest -f number --rpc-url $script:RPC)

# --- The three ballots: support 1 (for), 0 (against), 2 (abstain)
$ballots = @(
  @("staker1", "1", "FOR",     "20000000000000000000000000000"),
  @("staker2", "0", "AGAINST", "7500000000000000000000000000"),
  @("staker3", "2", "ABSTAIN", "5000000000000000000000000000")
)
$n = 2
$hashes = @{}
foreach ($b in $ballots) {
  $who = $b[0]
  $vpSnap = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:AddrBook.$who, "$($p.snapshotBlock)")
  $h = Send $who $st.governor "castVote(uint256,uint8)" @($propId, $b[1])
  $hashes[$who] = $h.hash
  $after = ReadProposal
  $tally = switch ($b[1]) { "1" { $after.forVotes } "0" { $after.againstVotes } "2" { $after.abstainVotes } }
  $hv = CQRaw $st.governor "hasVoted(uint256,address)(bool)" @($propId, $script:AddrBook.$who)
  $ok = ("$tally" -eq $b[3] -and "$vpSnap" -eq $b[3] -and $hv -eq "true")
  Log-Step "P2.1b.$n" "$who casts $($b[2]) (support=$($b[1])) with its snapshot weight" "weight = $($b[3]) wei lands in the $($b[2].ToLower()) tally; hasVoted=true" "vpAtSnapshot=$(FmtB $vpSnap), tally after=$(FmtB $tally) ($tally wei), hasVoted=$hv; gas=$($h.gasUsed)" $h.hash $(if ($ok) { "PASS" } else { "DEVIATION" })
  $n++
}

# --- P2.1b.5: the full tally, exact to the wei, read back in one shot
$p2 = ReadProposal
$ok5 = ("$($p2.forVotes)" -eq "20000000000000000000000000000" -and "$($p2.againstVotes)" -eq "7500000000000000000000000000" -and "$($p2.abstainVotes)" -eq "5000000000000000000000000000")
Log-Step "P2.1b.5" "Tally read back from proposals($propId)" "for=20000000000000000000000000000, against=7500000000000000000000000000, abstain=5000000000000000000000000000 wei -- exact" "for=$(FmtB $p2.forVotes) ($($p2.forVotes) wei), against=$(FmtB $p2.againstVotes) ($($p2.againstVotes) wei), abstain=$(FmtB $p2.abstainVotes) ($($p2.abstainVotes) wei)" "-" $(if ($ok5) { "PASS" } else { "DEVIATION" })

# --- P2.1b.6: quorum arithmetic from chain values; state stays Active until voteEnd
$quorumVotes = $p2.forVotes + $p2.abstainVotes
$quorumNeeded = [System.Numerics.BigInteger]::Divide($p2.snapTotal * $p2.quorumBps, 10000)
$stateNow = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$ok6 = ($quorumVotes -ge $quorumNeeded -and $p2.forVotes -gt $p2.againstVotes -and $stateNow -eq "1")
Log-Step "P2.1b.6" "Quorum on for+abstain (against excluded by design, #A3); outcome sealed only at voteEnd" "quorumVotes 25B >= needed 3.25B (10% of snapshot 32.5B); for > against; state still Active" "quorumVotes=$(FmtB $quorumVotes), needed=$(FmtB $quorumNeeded), for>against=$($p2.forVotes -gt $p2.againstVotes), state=$stateNow (1=Active until $(UtcOf $p2.voteEnd) UTC)" "-" $(if ($ok6) { "PASS" } else { "DEVIATION" })

# --- P2.1b.7: a second ballot from the same voter is refused
$rv = Expect-Revert "staker1" $st.governor "castVote(uint256,uint8)" @($propId, "1") "AlreadyVoted()"
Log-Step "P2.1b.7" "staker1 tries to vote a second time" "refused: AlreadyVoted -- no ballot can be counted twice" "$rv" "-" $(if ($rv -match "AlreadyVoted") { "PASS" } else { "DEVIATION" })

Log-Note "The plan for today named the three voters (staker1/2/3) but not their directions. The choice above -- one ballot per support value, mirroring day 1's three-stakers-three-tiers pattern -- exercises all three castVote branches and the quorum-excludes-against rule on a public chain, with weights distinct enough that the tally alone attributes every ballot. The outcome is unchanged: forVotes 20B > againstVotes 7.5B, quorum 25B >= 3.25B, so the proposal heads for Succeeded at voteEnd and the execute-~day-13 calendar stands. Recorded as a choice the plan left open, not a deviation from anything it specified."

# --- P3.14: VoteCast read back the way the monitor will read it
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$r = (cast logs --address $st.governor "VoteCast(uint256,address,uint8,uint256)" --from-block $fromBlock --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
$ErrorActionPreference = $prev
$evs = $r | ConvertFrom-Json
$count = if ($null -eq $evs) { 0 } else { ([array]$evs).Count }
$decoded = @()
foreach ($ev in [array]$evs) {
  $voter = "0x" + $ev.topics[2].Substring(26)
  $support = [System.Numerics.BigInteger]::Parse("0" + $ev.data.Substring(2, 64), "AllowHexSpecifier")
  $weight = [System.Numerics.BigInteger]::Parse("0" + $ev.data.Substring(66, 64), "AllowHexSpecifier")
  $decoded += "support=$support weight=$(FmtB $weight) voter=$voter"
}
$okEv = ($count -eq 3)
Log-Step "P3.14" "Read back: VoteCast(uint256,address,uint8,uint256) on governor" "exactly 3 -- one per ballot, supports 1/0/2 with the snapshot weights" "found=$count; $($decoded -join '; ')" "-" $(if ($okEv) { "PASS" } else { "DEVIATION" })

Write-Output "P4 COMPLETE proposal=$propId for=$($p2.forVotes) against=$($p2.againstVotes) abstain=$($p2.abstainVotes)"
Write-Output "hashes: staker1=$($hashes.staker1) staker2=$($hashes.staker2) staker3=$($hashes.staker3)"

